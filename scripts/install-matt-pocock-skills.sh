#!/usr/bin/env bash
set -euo pipefail

SCRIPT_SOURCE="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" >/dev/null 2>&1 && pwd -P)"
NEW_INSTALLER="${SCRIPT_DIR}/install-agent-setup.sh"
AGENT_SETUP_RAW_BASE="${AGENT_SETUP_RAW_BASE:-${RAW_BASE:-https://raw.githubusercontent.com/li-daqian/dev-toolbox/main}}"

usage() {
  cat <<'EOF'
Compatibility wrapper. New commands should use scripts/install-agent-setup.sh.

Legacy usage:
  ./scripts/install-matt-pocock-skills.sh work [options]
  ./scripts/install-matt-pocock-skills.sh personal [options]
  ./scripts/install-matt-pocock-skills.sh auto-update <enable|disable|status> [options]
EOF
}

[[ $# -gt 0 ]] || {
  usage
  exit 1
}

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
  usage
  exit 0
fi

LEGACY_COMMAND="$1"
shift
NEW_ARGS=()
case "$LEGACY_COMMAND" in
  work)
    NEW_ARGS=(skills --profile work --scope user --agent codex)
    ;;
  personal)
    NEW_ARGS=(skills --profile personal --scope project --agent codex)
    ;;
  auto-update)
    [[ $# -gt 0 ]] || {
      printf 'Error: auto-update requires an action.\n' >&2
      exit 1
    }
    AUTO_ACTION="$1"
    shift
    NEW_ARGS=(auto-update "$AUTO_ACTION" --profile work --agent codex)
    ;;
  *)
    printf 'Error: legacy profile must be one of: work, personal, auto-update\n' >&2
    exit 1
    ;;
esac
NEW_ARGS+=("$@")

if [[ -f "$NEW_INSTALLER" ]]; then
  exec bash "$NEW_INSTALLER" "${NEW_ARGS[@]}"
fi

command -v curl >/dev/null 2>&1 || {
  printf 'Error: curl is required to download install-agent-setup.sh.\n' >&2
  exit 1
}
curl -fsSL "${AGENT_SETUP_RAW_BASE}/scripts/install-agent-setup.sh?$(date +%s)" |
  AGENT_SETUP_RAW_BASE="$AGENT_SETUP_RAW_BASE" bash -s -- "${NEW_ARGS[@]}"
