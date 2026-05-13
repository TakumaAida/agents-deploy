#!/usr/bin/env bash
# deploy_mcp.sh — .agents/mcp.json -> Claude settings.json.mcpServers & Codex config.toml [mcp_servers.*]
#
# Source shape:
#   {
#     "servers": {
#       "linear": { "url": "https://mcp.linear.app/mcp" },
#       "github": { "command": "npx", "args": [...] }
#     }
#   }

# shellcheck disable=SC2148

_src="$SOURCE_DIR/mcp.json"

if [[ ! -f "$_src" ]]; then
  log_warn "mcp: $_src not found — skipping"
  return 0
fi

# Empty servers? Skip
_count="$(jq -r '.servers // {} | length' "$_src")"
if [[ "$_count" -eq 0 ]]; then
  log_info "mcp: no servers defined — skipping"
  return 0
fi

# ---------- Claude ----------

if [[ "$ONLY" != "codex" ]]; then
  _dst="$TARGET_DIR/.claude/settings.json"
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[dry-run] would merge mcpServers into: $_dst"
  else
    mkdir -p "$(dirname "$_dst")"
    [[ -f "$_dst" ]] || echo '{}' > "$_dst"
    _tmp="$(mktemp)"
    jq --slurpfile new "$_src" \
       '.mcpServers = ((.mcpServers // {}) + ($new[0].servers // {}))' \
       "$_dst" > "$_tmp"
    mv "$_tmp" "$_dst"
    log_info "merged mcpServers into: $_dst"
  fi
fi

# ---------- Codex ----------

if [[ "$ONLY" != "claude" ]]; then
  _cfg="$TARGET_DIR/.codex/config.toml"
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[dry-run] would merge mcp_servers into: $_cfg"
  else
    mkdir -p "$(dirname "$_cfg")"
    [[ -f "$_cfg" ]] || : > "$_cfg"
    # Build a JSON payload shaped as { "mcp_servers": { ... } } for deep-merge
    _tmp_payload="$(mktemp)"
    jq '{mcp_servers: (.servers // {})}' "$_src" > "$_tmp_payload"
    python3 "$TOOLS_DIR/toml_merge.py" --file "$_cfg" --merge-json "$_tmp_payload"
    rm -f "$_tmp_payload"
    log_info "merged mcp_servers into: $_cfg"
  fi
fi
