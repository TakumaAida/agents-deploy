#!/usr/bin/env bash
# deploy_settings.sh — merge tool-specific settings into the final config files.
#
# This phase runs LAST so it can override anything written by hooks/permissions/mcp.
#
# Sources:
#   .agents/settings/claude.json   ->  merged into .claude/settings.json (jq deep merge)
#   .agents/settings/codex.toml    ->  merged into .codex/config.toml   (tomlkit deep merge)
#
# Per-subagent Codex overrides (.agents/settings/codex-agents.toml) are consumed
# by deploy_agents.sh, not here.

# shellcheck disable=SC2148

_src_claude="$SOURCE_DIR/settings/claude.json"
_src_codex="$SOURCE_DIR/settings/codex.toml"

# ---------- Claude ----------

if [[ "$ONLY" != "codex" ]] && [[ -f "$_src_claude" ]]; then
  _dst="$TARGET_DIR/.claude/settings.json"
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[dry-run] would deep-merge settings into: $_dst"
  else
    mkdir -p "$(dirname "$_dst")"
    [[ -f "$_dst" ]] || echo '{}' > "$_dst"
    # Deep-merge using jq. Object-typed leaves merge recursively, scalars/arrays overwrite.
    # Note: must bind args as $values (not filters) so recursion sees the actual data.
    _tmp="$(mktemp)"
    jq --slurpfile new "$_src_claude" '
      def deep_merge($a; $b):
        if ($a|type) == "object" and ($b|type) == "object" then
          reduce (($a|keys_unsorted) + ($b|keys_unsorted) | unique[]) as $k
            ({}; .[$k] = deep_merge($a[$k]; $b[$k]))
        elif $b == null then $a
        else $b end;
      deep_merge(.; $new[0])
    ' "$_dst" > "$_tmp"
    mv "$_tmp" "$_dst"
    log_info "merged settings into: $_dst"
  fi
fi

# ---------- Codex ----------

if [[ "$ONLY" != "claude" ]] && [[ -f "$_src_codex" ]]; then
  _cfg="$TARGET_DIR/.codex/config.toml"
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[dry-run] would deep-merge settings into: $_cfg"
  else
    mkdir -p "$(dirname "$_cfg")"
    [[ -f "$_cfg" ]] || : > "$_cfg"
    python3 "$TOOLS_DIR/toml_merge.py" --file "$_cfg" --merge-toml "$_src_codex"
    log_info "merged settings into: $_cfg"
  fi
fi
