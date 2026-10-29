#!/usr/bin/env bash
set -euo pipefail

SCRIPT_SOURCE="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="${AGENT_SETUP_BUNDLE_ROOT:-$(cd "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd -P)}"
AGENT_SETUP_RAW_BASE="${AGENT_SETUP_RAW_BASE:-${RAW_BASE:-https://raw.githubusercontent.com/li-daqian/dev-toolbox/main}}"

required_bundle_files() {
  printf '%s\n' \
    scripts/install-agent-setup.sh \
    scripts/lib/agent-setup/common.sh \
    scripts/lib/agent-setup/instructions.sh \
    agent/global-instructions.md
}

bundle_is_complete() {
  local relative_path
  while IFS= read -r relative_path; do
    [[ -f "${REPO_ROOT}/${relative_path}" ]] || return 1
  done < <(required_bundle_files)
}

download_ephemeral_bundle() {
  local bundle_root
  local relative_path
  local status

  command -v curl >/dev/null 2>&1 || {
    printf 'Error: curl is required to download the Agent setup bundle.\n' >&2
    exit 1
  }
  bundle_root="$(mktemp -d)"
  trap 'rm -rf -- "$bundle_root"' EXIT

  while IFS= read -r relative_path; do
    mkdir -p "${bundle_root}/$(dirname "$relative_path")"
    curl -fsSL "${AGENT_SETUP_RAW_BASE}/${relative_path}?$(date +%s)" \
      -o "${bundle_root}/${relative_path}"
  done < <(required_bundle_files)

  AGENT_SETUP_BUNDLE_ROOT="$bundle_root" \
    bash "${bundle_root}/scripts/install-agent-setup.sh" "$@" || status=$?
  status="${status:-0}"
  exit "$status"
}

if ! bundle_is_complete; then
  if [[ -d "${REPO_ROOT}/.git" ]]; then
    printf 'Error: local Agent setup bundle is incomplete under %s.\n' "$REPO_ROOT" >&2
    exit 1
  fi
  download_ephemeral_bundle "$@"
fi

# shellcheck source=scripts/lib/agent-setup/common.sh
source "${REPO_ROOT}/scripts/lib/agent-setup/common.sh"
# shellcheck source=scripts/lib/agent-setup/instructions.sh
source "${REPO_ROOT}/scripts/lib/agent-setup/instructions.sh"

COMMAND=""
AGENT_TARGET="both"
DRY_RUN="false"
STDOUT_ONLY="false"
INSTRUCTIONS_TEMPLATE="${REPO_ROOT}/agent/global-instructions.md"
CLAUDE_HOME_DIR="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"
CODEX_HOME_DIR="${CODEX_HOME:-${HOME}/.codex}"
CODEX_INSTRUCTIONS_PATH="${CODEX_HOME_DIR}/AGENTS.md"
CLAUDE_INSTRUCTIONS_PATH="${CLAUDE_HOME_DIR}/CLAUDE.md"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/install-agent-setup.sh setup [options]
  ./scripts/install-agent-setup.sh instructions [options]

Both commands install global instructions only. Skills use plugin marketplaces.

Options:
  --agent <codex|claude|both>  Agent destination. Default: both
  --codex-path <path>          Override Codex global instruction file
  --claude-path <path>         Override Claude Code global instruction file
  --dry-run                   Preview without writing
  --stdout                    Print the instruction template (instructions only)
  --help                      Show this help
EOF
}

if [[ $# -eq 0 ]]; then
  usage
  exit 0
fi

case "$1" in
  setup|instructions)
    COMMAND="$1"
    shift
    ;;
  --help|-h)
    usage
    exit 0
    ;;
  *)
    fail "unknown command: $1"
    ;;
esac

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent|--target)
      [[ $# -ge 2 ]] || fail "$1 requires a value"
      AGENT_TARGET="$2"
      shift 2
      ;;
    --codex-path)
      [[ $# -ge 2 ]] || fail "--codex-path requires a value"
      CODEX_INSTRUCTIONS_PATH="$2"
      shift 2
      ;;
    --claude-path)
      [[ $# -ge 2 ]] || fail "--claude-path requires a value"
      CLAUDE_INSTRUCTIONS_PATH="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    --stdout)
      STDOUT_ONLY="true"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

detect_platform
validate_common_values

if [[ "$STDOUT_ONLY" == "true" ]]; then
  [[ "$COMMAND" == "instructions" ]] || fail "--stdout is supported only by the instructions command"
  [[ -f "$INSTRUCTIONS_TEMPLATE" ]] || fail "missing instruction template: ${INSTRUCTIONS_TEMPLATE}"
  command cat "$INSTRUCTIONS_TEMPLATE"
  exit 0
fi

install_instructions
