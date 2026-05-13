#!/usr/bin/env bash
# deploy_hooks.sh — .agents/hooks/events.json + scripts/ -> Claude & Codex hook configs
#
# Claude:
#   - .agents/hooks/events.json's contents merged into .claude/settings.json.hooks (via jq)
#   - .agents/hooks/scripts/* mirrored into .claude/hooks/scripts/
#
# Codex:
#   - Filtered events written to .codex/hooks.json (only supported event names)
#   - .codex/config.toml ensured to have [features] codex_hooks = true (via toml_merge.py)
#   - .agents/hooks/scripts/* mirrored into .codex/hooks/scripts/

# shellcheck disable=SC2148

_src_events="$SOURCE_DIR/hooks/events.json"
_src_scripts="$SOURCE_DIR/hooks/scripts"

if [[ ! -f "$_src_events" ]] && [[ ! -d "$_src_scripts" ]]; then
  log_warn "hooks: no .agents/hooks/ content — skipping"
  return 0
fi

# Codex-supported events (per docs current as of 2026-05)
_CODEX_SUPPORTED="PreToolUse PostToolUse UserPromptSubmit SessionStart Stop"

# ---------- Claude side ----------

if [[ "$ONLY" != "codex" ]] && [[ -f "$_src_events" ]]; then
  _dst="$TARGET_DIR/.claude/settings.json"
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[dry-run] would merge hooks into: $_dst"
  else
    mkdir -p "$(dirname "$_dst")"
    # Initialize settings.json if missing
    [[ -f "$_dst" ]] || echo '{}' > "$_dst"
    # Merge: .hooks = (.hooks // {}) + <events>
    _tmp="$(mktemp)"
    jq --slurpfile new "$_src_events" \
       '.hooks = ((.hooks // {}) + $new[0])' \
       "$_dst" > "$_tmp"
    mv "$_tmp" "$_dst"
    log_info "merged hooks into: $_dst"
  fi
fi

if [[ "$ONLY" != "codex" ]] && [[ -d "$_src_scripts" ]]; then
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[dry-run] would mirror scripts: .claude/hooks/scripts/"
  else
    copy_dir "$_src_scripts" "$TARGET_DIR/.claude/hooks/scripts"
  fi
fi

# ---------- Codex side ----------

if [[ "$ONLY" != "claude" ]] && [[ -f "$_src_events" ]]; then
  _dst="$TARGET_DIR/.codex/hooks.json"
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[dry-run] would write filtered hooks: $_dst"
  else
    mkdir -p "$(dirname "$_dst")"
    # Filter: only keep keys in _CODEX_SUPPORTED
    _supported_args=()
    for e in $_CODEX_SUPPORTED; do _supported_args+=("--arg" "e_${e}" "$e"); done
    _filtered="$(jq --argjson supported "$(printf '%s\n' $_CODEX_SUPPORTED | jq -R . | jq -s .)" \
        '{hooks: (to_entries | map(select(.key as $k | $supported | index($k))) | from_entries)}' \
        "$_src_events")"
    printf '%s\n' "$_filtered" > "$_dst"
    log_info "wrote filtered hooks: $_dst"

    # Warn about excluded events
    _dropped="$(jq -r --argjson supported "$(printf '%s\n' $_CODEX_SUPPORTED | jq -R . | jq -s .)" \
        '. | keys[] | select(. as $k | ($supported | index($k)) | not)' "$_src_events")"
    if [[ -n "$_dropped" ]]; then
      while IFS= read -r ev; do
        log_warn "Codex unsupported hook event: $ev — skipped"
      done <<< "$_dropped"
    fi
  fi

  # Ensure config.toml has [features] codex_hooks = true and [projects."<DIR>"] trust
  _cfg="$TARGET_DIR/.codex/config.toml"
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[dry-run] would ensure: $_cfg [features] codex_hooks=true and [projects.\"$TARGET_DIR\"] trust_level"
  else
    mkdir -p "$(dirname "$_cfg")"
    [[ -f "$_cfg" ]] || : > "$_cfg"
    python3 "$TOOLS_DIR/toml_merge.py" \
      --file "$_cfg" \
      --set "features.codex_hooks=true" \
      --set "projects.\"$TARGET_DIR\".trust_level=\"trusted\""
    log_info "ensured: $_cfg [features] codex_hooks=true"
  fi
fi

if [[ "$ONLY" != "claude" ]] && [[ -d "$_src_scripts" ]]; then
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[dry-run] would mirror scripts: .codex/hooks/scripts/"
  else
    copy_dir "$_src_scripts" "$TARGET_DIR/.codex/hooks/scripts"
  fi
fi
