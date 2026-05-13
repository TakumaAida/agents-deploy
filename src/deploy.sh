#!/usr/bin/env bash
# agents-deploy — deploy .agents/ to Claude Code and Codex CLI
#
# Reads <DIR>/.agents/ and writes <DIR>/.claude/, <DIR>/.codex/,
# <DIR>/CLAUDE.md and <DIR>/AGENTS.md.

set -euo pipefail

# ---------- resolve self ----------

# Find src/ directory through any symlinks, then source common.sh
_self_source="${BASH_SOURCE[0]}"
while [[ -L "$_self_source" ]]; do
  _target="$(readlink "$_self_source")"
  if [[ "$_target" = /* ]]; then
    _self_source="$_target"
  else
    _self_source="$(cd "$(dirname "$_self_source")" && pwd)/$_target"
  fi
done
SRC_DIR="$(cd "$(dirname "$_self_source")" && pwd)"
LIB_DIR="$SRC_DIR/lib"
TOOLS_DIR="$SRC_DIR/tools"
export SRC_DIR LIB_DIR TOOLS_DIR

# shellcheck source=lib/common.sh
. "$LIB_DIR/common.sh"

# ---------- argument parsing ----------

usage() {
  cat <<'USAGE'
agents-deploy — deploy .agents/ to Claude Code and Codex CLI

Usage:
  agents-deploy [options]

Options:
  --dir=<path>             .agents/ を持つディレクトリ (デフォルト: CWD)
  --only=claude|codex      片側だけデプロイ
  --skip=<a,b,c>           特定アセットをスキップ (comma-separated)
                           対象: instructions,skills,agents,hooks,permissions,mcp,settings
  --dry-run                書き込まずに差分のみ表示
  --force                  既存ファイルを問答無用で上書き
  --check-deps             依存ツールの有無を確認して終了
  -h, --help               このヘルプを表示
USAGE
}

DIR=""
ONLY=""
SKIP=""
DRY_RUN=0
FORCE=0

for arg in "$@"; do
  case "$arg" in
    --dir=*)        DIR="${arg#--dir=}" ;;
    --only=*)       ONLY="${arg#--only=}" ;;
    --skip=*)       SKIP="${arg#--skip=}" ;;
    --dry-run)      DRY_RUN=1 ;;
    --force)        FORCE=1 ;;
    --check-deps)   check_deps; exit $? ;;
    -h|--help)      usage; exit 0 ;;
    *)              die "Unknown option: $arg (use --help)" ;;
  esac
done

export DRY_RUN FORCE

# Default --dir to CWD
if [[ -z "$DIR" ]]; then
  DIR="$(pwd)"
else
  DIR="$(cd "$DIR" && pwd)"
fi
TARGET_DIR="$DIR"
SOURCE_DIR="$DIR/.agents"
export TARGET_DIR SOURCE_DIR

# Validate
if [[ ! -d "$SOURCE_DIR" ]]; then
  log_error "No .agents/ found in: $DIR"
  log_error "Create it first:  mkdir -p $DIR/.agents"
  log_error "See the repo's .agents/ for a working example."
  exit 1
fi

# Validate --only
case "$ONLY" in
  "" | claude | codex) ;;
  *) die "--only must be 'claude' or 'codex' (got: $ONLY)" ;;
esac
export ONLY

# Parse --skip into a space-padded string for portable lookup (bash 3.2 has no -A)
_SKIP_LIST=" "
if [[ -n "$SKIP" ]]; then
  IFS=',' read -ra _parts <<< "$SKIP"
  for p in "${_parts[@]}"; do
    case "$p" in
      instructions|skills|agents|hooks|permissions|mcp|settings) _SKIP_LIST="${_SKIP_LIST}${p} " ;;
      "") ;;
      *) die "--skip: unknown asset '$p' (allowed: instructions,skills,agents,hooks,permissions,mcp,settings)" ;;
    esac
  done
fi
skip_asset() { [[ "$_SKIP_LIST" == *" $1 "* ]]; }

# ---------- dependency check ----------

check_deps >/dev/null || die "Dependencies missing. Run 'agents-deploy --check-deps' for details."

# ---------- dispatch ----------

log_info "Source : $SOURCE_DIR"
log_info "Target : $TARGET_DIR"
[[ "$DRY_RUN" == "1" ]] && log_info "Mode   : dry-run (no writes)"
[[ -n "$ONLY"        ]] && log_info "Only   : $ONLY"
[[ -n "$SKIP"        ]] && log_info "Skip   : $SKIP"

run_phase() {
  local name="$1" script="$2"
  if skip_asset "$name"; then
    log_info "skip: $name"
    return 0
  fi
  if [[ -f "$LIB_DIR/$script" ]]; then
    # shellcheck disable=SC1090
    . "$LIB_DIR/$script"
  else
    log_warn "missing module: $script (phase not yet implemented)"
  fi
}

run_phase instructions deploy_instructions.sh
run_phase skills       deploy_skills.sh
run_phase agents       deploy_agents.sh
run_phase hooks        deploy_hooks.sh
run_phase permissions  deploy_permissions.sh
run_phase mcp          deploy_mcp.sh
# settings runs LAST so tool-specific overrides win over common merges above.
run_phase settings     deploy_settings.sh

log_info "Done."
