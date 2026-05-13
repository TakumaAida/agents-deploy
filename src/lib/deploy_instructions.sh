#!/usr/bin/env bash
# deploy_instructions.sh — .agents/AGENTS.md -> <TARGET>/CLAUDE.md & <TARGET>/AGENTS.md
#
# Optionally splits per-tool sections marked with HTML comments:
#   <!-- claude-only:start --> ... <!-- claude-only:end -->
#   <!-- codex-only:start  --> ... <!-- codex-only:end  -->

# shellcheck disable=SC2148

_src="$SOURCE_DIR/AGENTS.md"

if [[ ! -f "$_src" ]]; then
  log_warn "instructions: $_src not found — skipping"
  return 0
fi

# strip_tool_block_for <tool> <input> <output>
# Removes the OTHER tool's exclusive blocks and unwraps own blocks.
_strip_blocks() {
  local tool="$1" in="$2" out="$3"
  # Remove blocks for the OTHER tool entirely, then strip OWN block markers.
  local other
  if [[ "$tool" == "claude" ]]; then other="codex"; else other="claude"; fi

  awk -v keep="$tool" -v drop="$other" '
    {
      line = $0
      # Toggle inside-drop block
      if (line ~ "<!-- " drop "-only:start -->") { in_drop = 1; next }
      if (line ~ "<!-- " drop "-only:end -->")   { in_drop = 0; next }
      if (in_drop) next
      # Strip keep markers (keep their content)
      if (line ~ "<!-- " keep "-only:start -->") next
      if (line ~ "<!-- " keep "-only:end -->")   next
      print line
    }
  ' "$in" > "$out"
}

_emit() {
  local tool="$1" dst="$2"
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[dry-run] would write: $dst"
    return 0
  fi
  mkdir -p "$(dirname "$dst")"
  _strip_blocks "$tool" "$_src" "$dst"
  log_info "wrote: $dst"
}

case "$ONLY" in
  ""|claude) _emit claude "$TARGET_DIR/CLAUDE.md" ;;
esac
case "$ONLY" in
  ""|codex) _emit codex "$TARGET_DIR/AGENTS.md" ;;
esac
