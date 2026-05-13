#!/usr/bin/env python3
"""agent_md_to_toml.py — convert a Claude subagent (.md) to a Codex subagent (.toml).

Input  (stdin or argv[1]): a Claude subagent file with YAML frontmatter:
    ---
    name: code-reviewer
    description: Reviews code for issues
    tools: [Read, Grep, Bash]   # optional, ignored unless --keep-claude-fields
    model: opus                  # optional, ignored
    color: blue                  # optional, ignored
    ---
    You are a code review specialist...
    (body becomes developer_instructions)

Output (stdout): TOML in Codex subagent shape:
    name = "code-reviewer"
    description = "Reviews code for issues"
    developer_instructions = \"\"\"
    You are a code review specialist...
    \"\"\"

Codex-specific override fields (model, model_reasoning_effort, sandbox_mode,
nickname_candidates, mcp_servers) can be merged in via --overrides=<path.toml>,
keyed by agent name.

Usage:
  python3 agent_md_to_toml.py [--overrides=<file.toml>] [<input.md>] > out.toml
"""

from __future__ import annotations

import argparse
import re
import sys
from typing import Any

import yaml
import tomlkit


FRONT_MATTER_RE = re.compile(r"^---\s*\n(.*?)\n---\s*\n(.*)\Z", re.DOTALL)


def parse_input(text: str) -> tuple[dict, str]:
    m = FRONT_MATTER_RE.match(text)
    if not m:
        print("[agent_md_to_toml] no YAML frontmatter found", file=sys.stderr)
        sys.exit(2)
    data = yaml.safe_load(m.group(1)) or {}
    if not isinstance(data, dict):
        print("[agent_md_to_toml] frontmatter is not a mapping", file=sys.stderr)
        sys.exit(2)
    return data, m.group(2)


def load_overrides(path: str | None, agent_name: str) -> dict[str, Any]:
    if not path:
        return {}
    try:
        with open(path, "r", encoding="utf-8") as f:
            doc = tomlkit.parse(f.read())
    except FileNotFoundError:
        return {}
    section = doc.get(agent_name)
    if section is None:
        return {}
    return dict(section)


def build_toml(name: str, description: str, body: str, overrides: dict[str, Any]) -> str:
    doc = tomlkit.document()
    doc["name"] = name
    doc["description"] = description

    # Body becomes developer_instructions as multi-line basic string.
    # tomlkit doesn't have a direct "literal multiline" helper that's stable,
    # so we use a multiline basic string. Backslashes and triple quotes are escaped.
    body = body.rstrip("\n")
    safe_body = body.replace("\\", "\\\\").replace('"""', '\\"\\"\\"')
    # Build raw TOML for the multi-line value, since tomlkit's multiline handling
    # for basic strings sometimes single-lines short content.
    base = tomlkit.dumps(doc)
    extra = f'developer_instructions = """\n{safe_body}\n"""\n'

    # Append override fields after developer_instructions (deterministic order)
    overrides_doc = tomlkit.document()
    for k, v in overrides.items():
        overrides_doc[k] = v
    overrides_str = tomlkit.dumps(overrides_doc) if overrides else ""

    return base + extra + overrides_str


def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser(prog="agent_md_to_toml")
    p.add_argument("--overrides", default=None, help="Path to codex-agent-overrides.toml")
    p.add_argument("input", nargs="?", default=None, help="Input .md path (default: stdin)")
    args = p.parse_args(argv[1:])

    if args.input:
        with open(args.input, "r", encoding="utf-8") as f:
            text = f.read()
    else:
        text = sys.stdin.read()

    data, body = parse_input(text)
    name = str(data.get("name", "")).strip()
    if not name:
        print("[agent_md_to_toml] missing 'name' in frontmatter", file=sys.stderr)
        return 2
    description = str(data.get("description", "")).strip()
    overrides = load_overrides(args.overrides, name)

    sys.stdout.write(build_toml(name, description, body, overrides))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
