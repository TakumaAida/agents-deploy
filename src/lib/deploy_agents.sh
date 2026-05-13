#!/usr/bin/env bash
# deploy_agents.sh — .agents/agents/<n>.md -> .claude/agents/<n>.md & .codex/agents/<n>.toml

# shellcheck disable=SC2148

_src_root="$SOURCE_DIR/agents"

if [[ ! -d "$_src_root" ]]; then
  log_warn "agents: $_src_root not found — skipping"
  return 0
fi

shopt -s nullglob

_dest_claude_dir="$TARGET_DIR/.claude/agents"
_dest_codex_dir="$TARGET_DIR/.codex/agents"
_overrides="$SOURCE_DIR/settings/codex-agents.toml"

for _src in "$_src_root"/*.md; do
  _name="$(basename "$_src" .md)"

  # Claude: copy as-is
  if [[ "$ONLY" != "codex" ]]; then
    if [[ "$DRY_RUN" == "1" ]]; then
      log_info "[dry-run] would copy: .claude/agents/$_name.md"
    else
      copy_file "$_src" "$_dest_claude_dir/$_name.md"
    fi
  fi

  # Codex: transform to TOML
  if [[ "$ONLY" != "claude" ]]; then
    if [[ "$DRY_RUN" == "1" ]]; then
      log_info "[dry-run] would transform: .codex/agents/$_name.toml"
    else
      mkdir -p "$_dest_codex_dir"
      if [[ -f "$_overrides" ]]; then
        python3 "$TOOLS_DIR/agent_md_to_toml.py" --overrides="$_overrides" "$_src" \
          > "$_dest_codex_dir/$_name.toml"
      else
        python3 "$TOOLS_DIR/agent_md_to_toml.py" "$_src" > "$_dest_codex_dir/$_name.toml"
      fi
      log_info "transformed: .codex/agents/$_name.toml"
    fi
  fi
done

shopt -u nullglob
