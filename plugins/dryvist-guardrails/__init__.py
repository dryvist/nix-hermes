"""Read-only Home Assistant and GitHub guardrails for Hermes tool calls."""

from __future__ import annotations

import os
import re
from collections.abc import Mapping
from typing import Any

_GITHUB_READONLY_ENV = "DRYVIST_GUARDRAILS_GITHUB_READONLY"
_GITHUB_COMMAND_ARGS = {"terminal": "command", "execute_code": "code"}
_GUARDED_TOOLS = frozenset({"ha_call_service", *_GITHUB_COMMAND_ARGS})

_DIRECT_GITHUB_WRITES = (
    re.compile(r"(?<![\w.-])gh\s+(?:pr|issue)\s+(?:create|comment|merge|close|edit|review)\b", re.IGNORECASE),
    re.compile(r"(?<![\w.-])gh\s+release\s+create\b", re.IGNORECASE),
    re.compile(r"(?<![\w.-])gh\s+repo\s+(?:create|delete|edit)\b", re.IGNORECASE),
    re.compile(r"(?<![\w.-])git\s+push\b", re.IGNORECASE),
)
_GH_API_CALL = re.compile(r"(?<![\w.-])gh\s+api\b([^;&|\n]*)", re.IGNORECASE)
_GH_API_WRITE_METHOD = re.compile(
    r"(?<!\S)(?:-X\s*(?:POST|PATCH|PUT|DELETE)\b|--method(?:=|\s+)(?:POST|PATCH|PUT|DELETE)\b)",
    re.IGNORECASE,
)
_GH_API_READ_METHOD = re.compile(
    r"(?<!\S)(?:-X\s*GET\b|--method(?:=|\s+)GET\b)", re.IGNORECASE
)
_GH_API_FIELDS = re.compile(
    r"(?<!\S)(?:--(?:field|raw-field)(?:=|\s|$)|-[fF](?:\s|=|[^\s;&|]*=))"
)

_HA_BLOCK_MESSAGE = "Home Assistant control is read-only except notifications."
_GITHUB_BLOCK_MESSAGE = "GitHub writes are disabled for this read-only profile."
_EVALUATION_ERROR_MESSAGE = "Guardrails could not safely check this tool call; it was blocked."


def _github_writes_read_only() -> bool:
    return os.environ.get(_GITHUB_READONLY_ENV, "").strip().lower() in {"1", "true"}


def _command_contains_github_write(command: str) -> bool:
    if any(pattern.search(command) for pattern in _DIRECT_GITHUB_WRITES):
        return True

    for match in _GH_API_CALL.finditer(command):
        arguments = match.group(1)
        if _GH_API_WRITE_METHOD.search(arguments):
            return True
        if not _GH_API_READ_METHOD.search(arguments) and _GH_API_FIELDS.search(arguments):
            return True
    return False


def _block(message: str) -> dict[str, str]:
    return {"action": "block", "message": message}


def _on_pre_tool_call(tool_name: str = "", args: Any = None, **_: Any) -> dict[str, str] | None:
    """Block only the two requested policy cases; return None for all other calls."""
    if not isinstance(tool_name, str) or tool_name not in _GUARDED_TOOLS:
        return None

    try:
        if tool_name == "ha_call_service":
            if not isinstance(args, Mapping):
                raise TypeError("Home Assistant arguments must be a mapping")
            return None if args.get("domain") == "notify" else _block(_HA_BLOCK_MESSAGE)

        if not _github_writes_read_only():
            return None
        if not isinstance(args, Mapping):
            raise TypeError("command tool arguments must be a mapping")
        command = args.get(_GITHUB_COMMAND_ARGS[tool_name])
        if not isinstance(command, str):
            raise TypeError("command tool argument must be a string")
        return _block(_GITHUB_BLOCK_MESSAGE) if _command_contains_github_write(command) else None
    except Exception:
        return _block(_EVALUATION_ERROR_MESSAGE)


def register(ctx: Any) -> None:
    ctx.register_hook("pre_tool_call", _on_pre_tool_call)
