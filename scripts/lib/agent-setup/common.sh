#!/usr/bin/env bash

log() {
  printf '%s\n' "$*"
}

warn() {
  printf 'Warning: %s\n' "$*" >&2
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

require_command() {
  command_exists "$1" || fail "$1 is required."
}

canonical_dir() {
  (cd "$1" >/dev/null 2>&1 && pwd -P)
}

portable_link_target() {
  local link_path="$1"
  local raw_target
  local candidate

  [[ -L "$link_path" ]] || return 1
  raw_target="$(readlink "$link_path")" || return 1
  case "$raw_target" in
    /*)
      candidate="$raw_target"
      ;;
    [A-Za-z]:/*)
      candidate="$raw_target"
      ;;
    *)
      candidate="$(dirname "$link_path")/$raw_target"
      ;;
  esac
  canonical_dir "$candidate"
}

path_is_within() {
  local candidate="$1"
  local root="$2"

  [[ "$candidate" == "$root" || "$candidate" == "$root"/* ]]
}

target_includes_agent() {
  local candidate="$1"
  [[ "$AGENT_TARGET" == "$candidate" || "$AGENT_TARGET" == "both" ]]
}

detect_platform() {
  if [[ -n "${AGENT_SETUP_PLATFORM:-}" ]]; then
    PLATFORM="$AGENT_SETUP_PLATFORM"
    return
  fi

  case "$(uname -s 2>/dev/null || printf unknown)" in
    Darwin)
      PLATFORM="macos"
      ;;
    Linux)
      if [[ -n "${WSL_DISTRO_NAME:-}" ]] || grep -qi microsoft /proc/version 2>/dev/null; then
        PLATFORM="wsl"
      else
        PLATFORM="linux"
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*)
      PLATFORM="windows-git-bash"
      ;;
    *)
      fail "unsupported platform; use Linux, macOS, WSL, or Windows Git Bash"
      ;;
  esac
}

is_copy_platform() {
  [[ "$PLATFORM" == "windows-git-bash" ]]
}

run_or_log() {
  if [[ "$DRY_RUN" == "true" ]]; then
    printf 'Would run:'
    printf ' %q' "$@"
    printf '\n'
    return
  fi
  "$@"
}

make_unique_timestamp() {
  local fraction
  fraction="$(date +%N 2>/dev/null || true)"
  case "$fraction" in
    ''|*[!0-9]*) fraction="$$" ;;
  esac
  printf '%s.%s.%s' "$(date +%Y%m%d%H%M%S)" "$fraction" "$$"
}

agent_user_skills_dir() {
  case "$1" in
    codex) printf '%s\n' "$CODEX_USER_SKILLS_DIR" ;;
    claude) printf '%s\n' "$CLAUDE_USER_SKILLS_DIR" ;;
    *) fail "unknown Agent: $1" ;;
  esac
}

agent_project_skills_dir() {
  local agent="$1"
  case "$agent" in
    codex) printf '%s\n' "${PROJECT_ROOT}/.agents/skills" ;;
    claude) printf '%s\n' "${PROJECT_ROOT}/.claude/skills" ;;
    *) fail "unknown Agent: $agent" ;;
  esac
}

agent_skills_dir() {
  local agent="$1"
  if [[ "$SCOPE" == "user" ]]; then
    agent_user_skills_dir "$agent"
  else
    agent_project_skills_dir "$agent"
  fi
}

resolve_project_root() {
  [[ "$SCOPE" == "project" ]] || return 0
  require_command git
  [[ -d "$PROJECT_DIR" ]] || fail "project directory does not exist: ${PROJECT_DIR}"
  PROJECT_ROOT="$(git -C "$PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null)" ||
    fail "project scope requires a Git repository: ${PROJECT_DIR}"
  PROJECT_ROOT="$(canonical_dir "$PROJECT_ROOT")"
}

validate_common_values() {
  case "$AGENT_TARGET" in codex|claude|both) ;; *) fail "agent must be one of: codex, claude, both" ;; esac
  case "$SCOPE" in user|project) ;; *) fail "scope must be one of: user, project" ;; esac
  if [[ -n "$PROFILE" ]]; then
    case "$PROFILE" in personal|work) ;; *) fail "profile must be one of: personal, work" ;; esac
  fi
}
