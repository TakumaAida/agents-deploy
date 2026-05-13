#!/usr/bin/env bash
# deploy_permissions.sh — .agents/permissions.yaml -> Claude settings.json.permissions
#                                                   & Codex .codex/rules/default.rules
#
# Source schema:
#   allow:
#     - command: ["./gradlew"]
#       style: prefix
#     - command: ["git", "commit", "-m"]
#       style: prefix
#   deny:
#     - command: ["rm", "-rf", "/"]
#       style: prefix
#
# Claude output: permissions.allow / permissions.deny are arrays of strings.
#   For each entry: if command is a single token (no spaces), produce
#   `Bash(<token>:*)`. Otherwise produce `Bash(<joined-with-spaces>:*)`.
#
# Codex output: prefix_rule(pattern=[...quoted entries...], decision="allow|deny")
#   one per line. Quoted in Python-style.

# shellcheck disable=SC2148

_src="$SOURCE_DIR/permissions.yaml"

if [[ ! -f "$_src" ]]; then
  log_warn "permissions: $_src not found — skipping"
  return 0
fi

if [[ "$ONLY" != "codex" ]]; then
  _dst="$TARGET_DIR/.claude/settings.json"
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[dry-run] would merge permissions into: $_dst"
  else
    mkdir -p "$(dirname "$_dst")"
    [[ -f "$_dst" ]] || echo '{}' > "$_dst"
    # Generate Claude-format JSON from YAML
    _tmp_perm="$(mktemp)"
    python3 - "$_src" > "$_tmp_perm" <<'PY'
import sys, json, yaml
src = sys.argv[1]
with open(src, 'r', encoding='utf-8') as f:
    doc = yaml.safe_load(f) or {}

def to_bash_pattern(cmd):
    if not isinstance(cmd, list):
        return None
    s = " ".join(str(x) for x in cmd)
    return f"Bash({s}:*)"

def collect(key):
    out = []
    for entry in (doc.get(key) or []):
        if not isinstance(entry, dict):
            continue
        pat = to_bash_pattern(entry.get("command"))
        if pat:
            out.append(pat)
    return out

print(json.dumps({"allow": collect("allow"), "deny": collect("deny")}))
PY
    _tmp_out="$(mktemp)"
    jq --slurpfile new "$_tmp_perm" \
       '.permissions = ((.permissions // {}) | .allow = (((.allow // []) + ($new[0].allow // [])) | unique) | .deny = (((.deny // []) + ($new[0].deny // [])) | unique))' \
       "$_dst" > "$_tmp_out"
    mv "$_tmp_out" "$_dst"
    rm -f "$_tmp_perm"
    log_info "merged permissions into: $_dst"
  fi
fi

if [[ "$ONLY" != "claude" ]]; then
  _dst="$TARGET_DIR/.codex/rules/default.rules"
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[dry-run] would write Codex rules: $_dst"
  else
    mkdir -p "$(dirname "$_dst")"
    python3 - "$_src" "$_dst" <<'PY'
import sys, yaml

src, dst = sys.argv[1], sys.argv[2]
with open(src, 'r', encoding='utf-8') as f:
    doc = yaml.safe_load(f) or {}

def emit_lines(entries, decision):
    out = []
    for entry in (entries or []):
        if not isinstance(entry, dict):
            continue
        cmd = entry.get("command")
        if not isinstance(cmd, list) or not cmd:
            continue
        items = ", ".join('"' + str(x).replace('"', '\\"') + '"' for x in cmd)
        out.append(f'prefix_rule(pattern=[{items}], decision="{decision}")')
    return out

lines = []
lines += emit_lines(doc.get("allow"), "allow")
lines += emit_lines(doc.get("deny"), "deny")

with open(dst, 'w', encoding='utf-8') as f:
    f.write("\n".join(lines) + ("\n" if lines else ""))
PY
    log_info "wrote Codex rules: $_dst"
  fi
fi
