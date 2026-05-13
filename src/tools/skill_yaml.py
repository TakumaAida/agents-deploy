#!/usr/bin/env python3
"""skill_yaml.py — transform SKILL.md frontmatter for Codex.

Reads a SKILL.md from stdin (or a path argument), and writes the transformed
SKILL.md to stdout. The transformation:

  - If the YAML frontmatter does not contain `metadata.short-description`,
    derive it from `description` (first sentence, up to 60 chars) or fall back
    to `name`, and inject it.
  - The body (after the second `---`) is preserved verbatim.

Usage:
  python3 skill_yaml.py codex < input.md > output.md
  python3 skill_yaml.py codex input.md > output.md

Modes:
  codex   add metadata.short-description if missing (default)
"""

from __future__ import annotations

import sys
import re
from io import StringIO
from typing import Optional

import yaml


FRONT_MATTER_RE = re.compile(r"^---\s*\n(.*?)\n---\s*\n(.*)\Z", re.DOTALL)


def split_frontmatter(text: str) -> tuple[Optional[dict], str, str]:
    """Return (parsed_yaml, raw_yaml_text, body). parsed_yaml is None if no frontmatter."""
    m = FRONT_MATTER_RE.match(text)
    if not m:
        return None, "", text
    raw_yaml = m.group(1)
    body = m.group(2)
    try:
        data = yaml.safe_load(raw_yaml) or {}
    except yaml.YAMLError as e:
        print(f"[skill_yaml] failed to parse frontmatter: {e}", file=sys.stderr)
        sys.exit(2)
    if not isinstance(data, dict):
        print("[skill_yaml] frontmatter is not a mapping", file=sys.stderr)
        sys.exit(2)
    return data, raw_yaml, body


def derive_short(desc: str, name: str) -> str:
    desc = (desc or "").strip()
    if desc:
        # Split on first sentence terminator (. or 。)
        for sep in (". ", "。"):
            if sep in desc:
                desc = desc.split(sep, 1)[0].rstrip(".") + ""
                break
        if len(desc) > 60:
            desc = desc[:60].rstrip() + "…"
        return desc
    return name or ""


def transform_codex(text: str) -> str:
    data, _raw, body = split_frontmatter(text)
    if data is None:
        # No frontmatter — pass through unchanged.
        return text

    name = str(data.get("name", "")).strip()
    desc = str(data.get("description", "")).strip()

    metadata = data.get("metadata")
    if not isinstance(metadata, dict):
        metadata = {}
    if not metadata.get("short-description"):
        metadata["short-description"] = derive_short(desc, name)
    data["metadata"] = metadata

    # Serialize back. Preserve a stable key order: name, description, metadata, then rest.
    ordered_keys = ["name", "description", "metadata"]
    out = {}
    for k in ordered_keys:
        if k in data:
            out[k] = data[k]
    for k, v in data.items():
        if k not in out:
            out[k] = v

    buf = StringIO()
    buf.write("---\n")
    yaml.safe_dump(
        out,
        buf,
        sort_keys=False,
        allow_unicode=True,
        default_flow_style=False,
        width=10_000,  # prevent line wrapping of long values
    )
    buf.write("---\n")
    buf.write(body)
    return buf.getvalue()


def main(argv: list[str]) -> int:
    mode = argv[1] if len(argv) >= 2 else "codex"
    if mode != "codex":
        print(f"[skill_yaml] unknown mode: {mode} (only 'codex' supported)", file=sys.stderr)
        return 2

    if len(argv) >= 3:
        with open(argv[2], "r", encoding="utf-8") as f:
            text = f.read()
    else:
        text = sys.stdin.read()

    sys.stdout.write(transform_codex(text))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
