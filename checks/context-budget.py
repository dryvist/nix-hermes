#!/usr/bin/env python3
"""Count bundle and composed profile SOUL files with the serving tokenizer."""

import argparse
import json
import re
import sys
from pathlib import Path

from tokenizers import Tokenizer


HEADING = re.compile(r"^#{1,6}\s+\S.*$")


def read_limit(limits, name):
    value = limits.get(name)
    if not isinstance(value, int) or value < 0:
        raise ValueError(f"limits.json must contain a non-negative integer {name!r}")
    return value


def token_count(tokenizer, text):
    return len(tokenizer.encode(text, add_special_tokens=False).ids)


def sections(text):
    heading = "(preamble)"
    lines = []
    for line in text.splitlines(keepends=True):
        if HEADING.match(line):
            if lines:
                yield heading, "".join(lines)
            heading = line.strip()
            lines = [line]
        else:
            lines.append(line)
    if lines:
        yield heading, "".join(lines)


def make_oversized_fixture(tokenizer, limits_path, output_path):
    limits = json.loads(Path(limits_path).read_text(encoding="utf-8"))
    base_limit = read_limit(limits, "soul_base_max_tokens")
    char_limit = read_limit(limits, "context_file_max_chars")
    word = next(
        (candidate for candidate in ("x", "a", "I", "0") if token_count(tokenizer, candidate) == 1),
        None,
    )
    if word is None:
        raise ValueError("could not find a single-token fixture word")

    text = word
    while token_count(tokenizer, text) <= base_limit:
        text += f" {word}"
    if len(text) > char_limit:
        raise ValueError("could not create a token-oversized fixture within the character limit")
    Path(output_path).write_text(text, encoding="utf-8")


def documents(bundle, base_text):
    yield "SOUL.md", base_text, "base"

    profile_dir = bundle / "soul" / "profiles"
    lifecycle_path = profile_dir / "kanban-lifecycle.md"
    profile_paths = sorted(path for path in profile_dir.glob("*.md") if path != lifecycle_path)
    if not profile_paths:
        return
    lifecycle = lifecycle_path.read_text(encoding="utf-8")
    for profile_path in profile_paths:
        profile = profile_path.read_text(encoding="utf-8")
        name = profile_path.relative_to(bundle).as_posix()
        yield f"{name} (composed)", f"{base_text}\n\n{profile}\n\n{lifecycle}", "profile"


def check_bundle(tokenizer, bundle_path, name):
    bundle = Path(bundle_path)
    limits = json.loads((bundle / "limits.json").read_text(encoding="utf-8"))
    base_limit = read_limit(limits, "soul_base_max_tokens")
    soul_limit = read_limit(limits, "soul_max_tokens")
    char_limit = read_limit(limits, "context_file_max_chars")
    base_text = (bundle / "SOUL.md").read_text(encoding="utf-8")

    results = []
    failures = []
    for filename, text, kind in documents(bundle, base_text):
        count = token_count(tokenizer, text)
        chars = len(text)
        result = (f"{name}/{filename}", text, count, chars)
        results.append(result)
        reasons = []
        budget = base_limit if kind == "base" else soul_limit
        budget_name = "soul_base_max_tokens" if kind == "base" else "soul_max_tokens"
        if count > budget:
            reasons.append(f"{count} tokens exceeds {budget_name} ({budget})")
        if chars > char_limit:
            reasons.append(f"{chars} chars exceeds context_file_max_chars ({char_limit})")
        if reasons:
            failures.append((result, reasons))

    return results, failures


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--tokenizer", required=True)
    parser.add_argument("--bundle")
    parser.add_argument("--name", default="bundle")
    parser.add_argument("--make-oversized-fixture")
    parser.add_argument("--limits")
    args = parser.parse_args()

    tokenizer = Tokenizer.from_file(args.tokenizer)
    if args.make_oversized_fixture:
        if not args.limits:
            parser.error("--limits is required with --make-oversized-fixture")
        make_oversized_fixture(tokenizer, args.limits, args.make_oversized_fixture)
        return 0
    if not args.bundle:
        parser.error("--bundle is required unless creating an oversized fixture")

    results, failures = check_bundle(tokenizer, args.bundle, args.name)
    print("bundle/file | tokens | chars")
    for filename, _, count, chars in results:
        print(f"{filename} | {count} | {chars}")

    for (filename, text, _, _), reasons in failures:
        print(f"\n{filename}: {'; '.join(reasons)}", file=sys.stderr)
        print("heading | tokens | chars", file=sys.stderr)
        for heading, section in sections(text):
            print(
                f"{heading} | {token_count(tokenizer, section)} | {len(section)}",
                file=sys.stderr,
            )

    return 1 if failures else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(error, file=sys.stderr)
        raise SystemExit(1)
