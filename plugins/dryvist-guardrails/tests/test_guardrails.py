"""Behavior checks for the dryvist-guardrails Hermes plugin."""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import unittest
from unittest.mock import patch

PLUGIN_DIR = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("dryvist_guardrails", PLUGIN_DIR / "__init__.py")
assert SPEC is not None and SPEC.loader is not None
guardrails = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(guardrails)


class GuardrailTests(unittest.TestCase):
    def call_with_flag(self, flag: str, tool_name: str, args: dict[str, str] | None) -> object:
        with patch.dict(os.environ, {guardrails._GITHUB_READONLY_ENV: flag}):
            return guardrails._on_pre_tool_call(tool_name, args)

    def test_blocks_home_assistant_control(self) -> None:
        result = guardrails._on_pre_tool_call(
            "ha_call_service", {"domain": "light", "service": "turn_on"}
        )
        self.assertEqual(result["action"], "block")
        self.assertIn("read-only except notifications", result["message"])

    def test_allows_home_assistant_notify(self) -> None:
        self.assertIsNone(
            guardrails._on_pre_tool_call(
                "ha_call_service", {"domain": "notify", "service": "mobile_app_x"}
            )
        )

    def test_allows_non_home_assistant_tool(self) -> None:
        self.assertIsNone(
            self.call_with_flag("true", "web_search", {"query": "gh pr create"})
        )

    def test_blocks_github_write_commands_when_enabled(self) -> None:
        for command in (
            "gh pr create --title test",
            "gh api repos/x/y -X POST",
            "gh api repos/x/y -f state=open",
            "git push origin HEAD",
        ):
            with self.subTest(command=command):
                result = self.call_with_flag("1", "terminal", {"command": command})
                self.assertEqual(result["action"], "block")

    def test_allows_reads_and_git_status(self) -> None:
        for command in ("gh api repos/x/y", "gh api repos/x/y -X GET -f per_page=10", "git status"):
            with self.subTest(command=command):
                self.assertIsNone(self.call_with_flag("true", "terminal", {"command": command}))

    def test_blocks_code_execution_writes(self) -> None:
        result = self.call_with_flag("1", "execute_code", {"code": "gh issue close 123"})
        self.assertEqual(result["action"], "block")

    def test_allows_github_writes_when_disabled(self) -> None:
        self.assertIsNone(self.call_with_flag("", "terminal", {"command": "gh pr create"}))

    def test_evaluation_error_blocks_only_guarded_tools(self) -> None:
        with (
            patch.dict(os.environ, {guardrails._GITHUB_READONLY_ENV: "1"}),
            patch.object(guardrails, "_command_contains_github_write", side_effect=RuntimeError),
        ):
            result = guardrails._on_pre_tool_call("terminal", {"command": "git status"})
            self.assertEqual(result["action"], "block")
            self.assertIsNone(guardrails._on_pre_tool_call("web_search", {"query": "test"}))


if __name__ == "__main__":
    unittest.main()
