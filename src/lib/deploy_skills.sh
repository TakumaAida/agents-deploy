#!/usr/bin/env bash
# deploy_skills.sh — .agents/skills/<n>/ -> .claude/skills/<n>/ & .codex/skills/<n>/
#
# Strategy:
#   - For each <n> under .agents/skills/, mirror the entire directory to both
#     .claude/skills/<n>/ and .codex/skills/<n>/.
#   - Replace SKILL.md on the Codex side with one transformed by skill_yaml.py
#     (adds metadata.short-description).

# shellcheck disable=SC2148

_src_root="$SOURCE_DIR/skills"

if [[ ! -d "$_src_root" ]]; then
  log_warn "skills: $_src_root not found — skipping"
  return 0
fi

shopt -s nullglob

_dest_claude="$TARGET_DIR/.claude/skills"
_dest_codex="$TARGET_DIR/.codex/skills"

for _skill_dir in "$_src_root"/*/; do
  _name="$(basename "$_skill_dir")"
  _src_skill_md="$_skill_dir/SKILL.md"
  [[ -f "$_src_skill_md" ]] || { log_warn "skills/$_name: no SKILL.md, skipping"; continue; }

  # Claude: mirror as-is
  if [[ "$ONLY" != "codex" ]]; then
    if [[ "$DRY_RUN" == "1" ]]; then
      log_info "[dry-run] would mirror: .claude/skills/$_name/"
    else
      copy_dir "$_skill_dir" "$_dest_claude/$_name"
    fi
  fi

  # Codex: mirror, then rewrite SKILL.md with transform
  if [[ "$ONLY" != "claude" ]]; then
    if [[ "$DRY_RUN" == "1" ]]; then
      log_info "[dry-run] would mirror+transform: .codex/skills/$_name/"
    else
      copy_dir "$_skill_dir" "$_dest_codex/$_name"
      python3 "$TOOLS_DIR/skill_yaml.py" codex "$_src_skill_md" > "$_dest_codex/$_name/SKILL.md"
      log_info "transformed: .codex/skills/$_name/SKILL.md"
    fi
  fi
done

shopt -u nullglob
