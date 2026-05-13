#!/usr/bin/env bash
# common.sh — shared helpers for agents-deploy
#
# Sourced by src/deploy.sh and lib/deploy_*.sh. Provides:
#   - log_*    : leveled logging
#   - die      : print error and exit
#   - resolve_self_dir : find src/ root through symlinks
#   - check_deps : verify jq, python3, tomlkit, pyyaml
#   - sha256_of  : hash a file
#   - has_cmd    : test command availability

set -euo pipefail

# ---------- logging ----------

_log() {
  local level="$1"; shift
  printf '[%s] %s\n' "$level" "$*" >&2
}
log_info()  { _log info  "$@"; }
log_warn()  { _log warn  "$@"; }
log_error() { _log error "$@"; }
log_debug() { [[ "${AGENTS_DEPLOY_DEBUG:-0}" == "1" ]] && _log debug "$@" || true; }

die() { log_error "$*"; exit 1; }

# ---------- path resolution ----------

# Resolve the canonical directory of this very script even when invoked through
# a symlink (which is the normal case once installed via ~/.local/bin).
# Echoes the absolute path of src/.
resolve_self_dir() {
  local source="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
  # Follow symlinks until we hit the real file
  while [[ -L "$source" ]]; do
    local target
    target="$(readlink "$source")"
    if [[ "$target" = /* ]]; then
      source="$target"
    else
      source="$(cd "$(dirname "$source")" && pwd)/$target"
    fi
  done
  local script_dir
  script_dir="$(cd "$(dirname "$source")" && pwd)"
  # src/deploy.sh lives in src/, so script_dir IS src/
  # but if sourced from lib/, climb one level
  case "$script_dir" in
    */lib) dirname "$script_dir" ;;
    *)     printf '%s' "$script_dir" ;;
  esac
}

# ---------- command checks ----------

has_cmd() { command -v "$1" >/dev/null 2>&1; }

check_deps() {
  local missing=()
  has_cmd jq      || missing+=("jq")
  has_cmd python3 || missing+=("python3")
  if has_cmd python3; then
    python3 -c 'import tomlkit' 2>/dev/null || missing+=("python3-tomlkit (pip install tomlkit)")
    python3 -c 'import yaml'    2>/dev/null || missing+=("python3-pyyaml (pip install pyyaml)")
  fi
  if has_cmd shasum; then :; elif has_cmd sha256sum; then :; else missing+=("shasum or sha256sum"); fi

  if (( ${#missing[@]} > 0 )); then
    log_error "Missing dependencies:"
    for m in "${missing[@]}"; do log_error "  - $m"; done
    return 1
  fi
  log_info "All dependencies present."
  return 0
}

# ---------- sha256 ----------

sha256_of() {
  local f="$1"
  if has_cmd shasum; then
    shasum -a 256 "$f" | awk '{print $1}'
  else
    sha256sum "$f" | awk '{print $1}'
  fi
}

# ---------- copy helper ----------

# copy_file <src> <dst>
# Creates parent dir, copies preserving mode. No-op if src == dst.
copy_file() {
  local src="$1" dst="$2"
  [[ -e "$src" ]] || die "copy_file: source not found: $src"
  mkdir -p "$(dirname "$dst")"
  if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
    log_debug "unchanged: $dst"
    return 0
  fi
  cp -p "$src" "$dst"
  log_info "wrote: $dst"
}

# copy_dir <src_dir> <dst_dir>
# Recursively mirrors src_dir into dst_dir (cp -R).
copy_dir() {
  local src="$1" dst="$2"
  [[ -d "$src" ]] || die "copy_dir: source not a directory: $src"
  mkdir -p "$dst"
  # use rsync if available for nicer diffs, else cp -R
  if has_cmd rsync; then
    rsync -a --delete-excluded "$src/" "$dst/"
  else
    cp -R "$src/." "$dst/"
  fi
  log_info "synced dir: $dst"
}
