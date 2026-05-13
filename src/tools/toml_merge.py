#!/usr/bin/env python3
"""toml_merge.py — in-place merge values into a TOML file (preserves comments/order).

Three modes:

1) --set <dotted.key>=<json-or-literal>   (repeatable)
   Sets individual values. Dotted keys auto-create nested tables.
   Value parsing:
     - "true" / "false"            -> bool
     - integer literal             -> int
     - float literal               -> float
     - JSON object/array (starts with { or [)  -> parsed via json.loads
     - quoted string ("..." or '...') -> string contents
     - otherwise                   -> string as-is

2) --merge-json <file>           (repeatable)
   Reads a JSON file like {"mcp_servers": {"linear": {"url": "..."}}}
   and recursively merges it into the document.

2b) --merge-toml <file>          (repeatable)
   Same as --merge-json, but reads a TOML file instead.

3) --section <prefix> --table <json-file>
   Replaces/creates a single TOML table at <prefix> with the contents of the
   JSON file. Useful for [mcp_servers.<name>] = {...}.

Usage examples:
  toml_merge.py --file config.toml --set 'features.codex_hooks=true'
  toml_merge.py --file config.toml --set 'projects."/Users/x/proj".trust_level="trusted"'
  toml_merge.py --file config.toml --merge-json mcp.json
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from typing import Any

import tomlkit
from tomlkit import items as tk_items


# ---------- dotted-key parsing ----------

# Split a dotted key like  features.codex_hooks
# or projects."/Users/x/proj".trust_level into segments.
_DOTTED_RE = re.compile(r'"([^"]*)"|([^.]+)')


def split_dotted(key: str) -> list[str]:
    parts: list[str] = []
    pos = 0
    while pos < len(key):
        # skip leading dots
        while pos < len(key) and key[pos] == ".":
            pos += 1
        if pos >= len(key):
            break
        if key[pos] == '"':
            # quoted segment
            end = key.find('"', pos + 1)
            if end < 0:
                raise ValueError(f"Unterminated quoted segment in key: {key!r}")
            parts.append(key[pos + 1 : end])
            pos = end + 1
        else:
            # unquoted segment until next .
            end = key.find(".", pos)
            if end < 0:
                parts.append(key[pos:])
                break
            parts.append(key[pos:end])
            pos = end
    return parts


# ---------- value parsing ----------

_INT_RE = re.compile(r"^-?\d+$")
_FLOAT_RE = re.compile(r"^-?\d+\.\d+$")


def parse_value(raw: str) -> Any:
    s = raw.strip()
    if s == "true":
        return True
    if s == "false":
        return False
    if _INT_RE.match(s):
        return int(s)
    if _FLOAT_RE.match(s):
        return float(s)
    if s and s[0] in "{[":
        try:
            return json.loads(s)
        except json.JSONDecodeError as e:
            print(f"[toml_merge] failed to parse JSON value {s!r}: {e}", file=sys.stderr)
            sys.exit(2)
    if len(s) >= 2 and s[0] == s[-1] and s[0] in ("'", '"'):
        return s[1:-1]
    return s


# ---------- set / merge primitives ----------

def _ensure_table(doc: Any, path: list[str]) -> Any:
    """Walk `doc` creating tables as needed, return the final container."""
    cur = doc
    for seg in path:
        existing = cur.get(seg) if hasattr(cur, "get") else None
        if existing is None or not isinstance(existing, (dict, tk_items.Table, tk_items.InlineTable)):
            new_table = tomlkit.table()
            cur[seg] = new_table
            cur = new_table
        else:
            cur = existing
    return cur


def set_dotted(doc: Any, dotted: str, value: Any) -> None:
    segments = split_dotted(dotted)
    if not segments:
        raise ValueError(f"empty key: {dotted!r}")
    *path, last = segments
    container = _ensure_table(doc, path) if path else doc
    container[last] = value


def deep_merge(doc: Any, other: dict) -> None:
    """Recursively merge `other` into `doc` (tomlkit doc / table)."""
    for k, v in other.items():
        if isinstance(v, dict):
            existing = doc.get(k) if hasattr(doc, "get") else None
            if isinstance(existing, (dict, tk_items.Table, tk_items.InlineTable)):
                deep_merge(existing, v)
            else:
                new_table = tomlkit.table()
                doc[k] = new_table
                deep_merge(new_table, v)
        else:
            doc[k] = v


# ---------- I/O ----------

def load_doc(path: str) -> Any:
    try:
        with open(path, "r", encoding="utf-8") as f:
            text = f.read()
    except FileNotFoundError:
        text = ""
    return tomlkit.parse(text) if text else tomlkit.document()


def save_doc(path: str, doc: Any) -> None:
    with open(path, "w", encoding="utf-8") as f:
        f.write(tomlkit.dumps(doc))


# ---------- CLI ----------

def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser(prog="toml_merge")
    p.add_argument("--file", required=True, help="TOML file to modify in-place")
    p.add_argument("--set", action="append", default=[], dest="sets",
                   help="dotted.key=value (repeatable)")
    p.add_argument("--merge-json", action="append", default=[], dest="merges",
                   help="JSON file to deep-merge at root (repeatable)")
    p.add_argument("--merge-toml", action="append", default=[], dest="merges_toml",
                   help="TOML file to deep-merge at root (repeatable)")
    p.add_argument("--section", default=None, help="prefix path for --table")
    p.add_argument("--table", default=None,
                   help="JSON file whose contents become the table at --section")
    args = p.parse_args(argv[1:])

    doc = load_doc(args.file)

    for entry in args.sets:
        if "=" not in entry:
            print(f"[toml_merge] --set expects 'key=value', got: {entry!r}", file=sys.stderr)
            return 2
        k, _, v = entry.partition("=")
        set_dotted(doc, k.strip(), parse_value(v))

    def _tomlkit_to_dict(node):
        if isinstance(node, (dict, tk_items.Table, tk_items.InlineTable)):
            return {k: _tomlkit_to_dict(v) for k, v in node.items()}
        if isinstance(node, list):
            return [_tomlkit_to_dict(v) for v in node]
        return node

    for mfile in args.merges:
        with open(mfile, "r", encoding="utf-8") as f:
            other = json.load(f)
        if not isinstance(other, dict):
            print(f"[toml_merge] --merge-json expects an object root in {mfile}", file=sys.stderr)
            return 2
        deep_merge(doc, other)

    for mfile in args.merges_toml:
        with open(mfile, "r", encoding="utf-8") as f:
            other_doc = tomlkit.parse(f.read())
        other = _tomlkit_to_dict(other_doc)
        if not isinstance(other, dict):
            print(f"[toml_merge] --merge-toml expects table root in {mfile}", file=sys.stderr)
            return 2
        deep_merge(doc, other)

    if args.section and args.table:
        with open(args.table, "r", encoding="utf-8") as f:
            payload = json.load(f)
        if not isinstance(payload, dict):
            print(f"[toml_merge] --table expects an object root in {args.table}", file=sys.stderr)
            return 2
        path = split_dotted(args.section)
        if not path:
            print("[toml_merge] --section is empty", file=sys.stderr)
            return 2
        *parent, last = path
        container = _ensure_table(doc, parent) if parent else doc
        new_table = tomlkit.table()
        deep_merge(new_table, payload)
        container[last] = new_table

    save_doc(args.file, doc)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
