#!/usr/bin/env bash
set -euo pipefail

SCRIPT_SOURCE="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" >/dev/null 2>&1 && pwd -P)"
NEW_INSTALLER="${SCRIPT_DIR}/install-agent-setup.sh"
AGENT_SETUP_RAW_BASE="${AGENT_SETUP_RAW_BASE:-${RAW_BASE:-https://raw.githubusercontent.com/li-daqian/dev-toolbox/main}}"
APPLY="false"
FORWARDED_ARGS=()

for argument in "$@"; do
  if [[ "$argument" == "--apply" ]]; then
    APPLY="true"
  else
    FORWARDED_ARGS+=("$argument")
  fi
done

if [[ "$APPLY" == "false" ]]; then
  FORWARDED_ARGS+=("--dry-run")
fi

if [[ -f "$NEW_INSTALLER" ]]; then
  exec bash "$NEW_INSTALLER" instructions "${FORWARDED_ARGS[@]}"
fi

command -v curl >/dev/null 2>&1 || {
  printf 'Error: curl is required to download install-agent-setup.sh.\n' >&2
  exit 1
}
curl -fsSL "${AGENT_SETUP_RAW_BASE}/scripts/install-agent-setup.sh?$(date +%s)" |
  AGENT_SETUP_RAW_BASE="$AGENT_SETUP_RAW_BASE" bash -s -- instructions "${FORWARDED_ARGS[@]}"
