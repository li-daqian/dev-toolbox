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

make_unique_timestamp() {
  local fraction
  fraction="$(date +%N 2>/dev/null || true)"
  case "$fraction" in
    ''|*[!0-9]*) fraction="$$" ;;
  esac
  printf '%s.%s.%s' "$(date +%Y%m%d%H%M%S)" "$fraction" "$$"
}

validate_common_values() {
  case "$AGENT_TARGET" in codex|claude|both) ;; *) fail "agent must be one of: codex, claude, both" ;; esac
}
