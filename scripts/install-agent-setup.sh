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
    scripts/lib/agent-setup/skills.sh \
    scripts/lib/agent-setup/auto-update.sh \
    agent/global-instructions.md \
    agent/skills/mattpocock-personal.txt \
    agent/skills/mattpocock-work.txt
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

  AGENT_SETUP_BUNDLE_ROOT="$bundle_root" AGENT_SETUP_EPHEMERAL="true" \
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
# shellcheck source=scripts/lib/agent-setup/skills.sh
source "${REPO_ROOT}/scripts/lib/agent-setup/skills.sh"
# shellcheck source=scripts/lib/agent-setup/auto-update.sh
source "${REPO_ROOT}/scripts/lib/agent-setup/auto-update.sh"

UPSTREAM_REPO="https://github.com/mattpocock/skills.git"
UPSTREAM_REF="main"
COMMAND=""
AUTO_UPDATE_ACTION=""
PROFILE=""
SCOPE="user"
AGENT_TARGET="both"
PROJECT_DIR="$PWD"
PROJECT_ROOT=""
DRY_RUN="false"
OFFLINE="false"
STDOUT_ONLY="false"
EXTERNAL_SOURCE_DIR=""
SOURCE_DIR=""
SOURCE_AVAILABLE="false"
MANIFEST_ROOT="${REPO_ROOT}/agent/skills"
INSTRUCTIONS_TEMPLATE="${REPO_ROOT}/agent/global-instructions.md"
MANAGED_SOURCE_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/codex-skill-sources/mattpocock-skills"
CODEX_USER_SKILLS_DIR="${HOME}/.agents/skills"
CLAUDE_HOME_DIR="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"
CLAUDE_USER_SKILLS_DIR="${CLAUDE_HOME_DIR}/skills"
CODEX_HOME_DIR="${CODEX_HOME:-${HOME}/.codex}"
CODEX_INSTRUCTIONS_PATH="${CODEX_HOME_DIR}/AGENTS.md"
CLAUDE_INSTRUCTIONS_PATH="${CLAUDE_HOME_DIR}/CLAUDE.md"
AUTO_UPDATE_CALENDAR="Mon *-*-* 09:00:00"
SYSTEMD_USER_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/systemd/user"
AUTO_UPDATE_STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/agent-setup"
INSTALLER_PATH="${SCRIPT_DIR}/$(basename "$SCRIPT_SOURCE")"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/install-agent-setup.sh setup --profile <personal|work> [options]
  ./scripts/install-agent-setup.sh instructions [options]
  ./scripts/install-agent-setup.sh skills --profile <personal|work> [options]
  ./scripts/install-agent-setup.sh auto-update <enable|disable|status> [options]

Commands:
  setup          Install global instructions and the selected skill profile
  instructions   Install global instructions only
  skills         Reconcile the selected skill profile only
  auto-update    Manage the Linux systemd user timer for user-scope skills

Dimensions:
  --profile <personal|work>    Exact desired skill set; required for setup/skills
  --scope <user|project>       Skill installation scope. Default: user
  --agent <codex|claude|both>  Agent destination. Default: both
  --project <path>             Git project for project scope. Default: current directory

Source options:
  --ref <git-ref>              Upstream Git ref. Default: main
  --source-root <path>         Managed upstream checkout
  --source-dir <path>          Existing checkout; never fetched or modified
  --offline                    Use an existing checkout without network access

Target overrides:
  --codex-user-skills-dir <path>
  --claude-user-skills-dir <path>
  --codex-path <path>
  --claude-path <path>

Updater options:
  --calendar <expression>      systemd calendar. Default: Mon *-*-* 09:00:00
  --systemd-user-dir <path>    systemd user unit directory
  --state-dir <path>           updater log directory

Other options:
  --dry-run                    Plan without fetching or writing
  --stdout                     Print the instruction template (instructions only)
  --help                       Show this help

Examples:
  ./scripts/install-agent-setup.sh setup --profile personal
  ./scripts/install-agent-setup.sh skills --profile work --scope project --agent codex
  ./scripts/install-agent-setup.sh skills --profile personal --offline
  ./scripts/install-agent-setup.sh auto-update enable --profile work --agent both
EOF
}

if [[ $# -eq 0 ]]; then
  usage
  exit 0
fi

case "$1" in
  setup|instructions|skills)
    COMMAND="$1"
    shift
    ;;
  auto-update)
    COMMAND="$1"
    shift
    [[ $# -gt 0 ]] || fail "auto-update requires an action: enable, disable, or status"
    AUTO_UPDATE_ACTION="$1"
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
    --profile)
      [[ $# -ge 2 ]] || fail "--profile requires a value"
      PROFILE="$2"
      shift 2
      ;;
    --scope)
      [[ $# -ge 2 ]] || fail "--scope requires a value"
      SCOPE="$2"
      shift 2
      ;;
    --agent|--target)
      [[ $# -ge 2 ]] || fail "$1 requires a value"
      AGENT_TARGET="$2"
      shift 2
      ;;
    --project)
      [[ $# -ge 2 ]] || fail "--project requires a value"
      PROJECT_DIR="$2"
      shift 2
      ;;
    --ref)
      [[ $# -ge 2 ]] || fail "--ref requires a value"
      UPSTREAM_REF="$2"
      shift 2
      ;;
    --source-root)
      [[ $# -ge 2 ]] || fail "--source-root requires a value"
      MANAGED_SOURCE_DIR="$2"
      shift 2
      ;;
    --source-dir)
      [[ $# -ge 2 ]] || fail "--source-dir requires a value"
      EXTERNAL_SOURCE_DIR="$2"
      shift 2
      ;;
    --codex-user-skills-dir|--user-skills-dir)
      [[ $# -ge 2 ]] || fail "$1 requires a value"
      CODEX_USER_SKILLS_DIR="$2"
      shift 2
      ;;
    --claude-user-skills-dir)
      [[ $# -ge 2 ]] || fail "--claude-user-skills-dir requires a value"
      CLAUDE_USER_SKILLS_DIR="$2"
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
    --calendar)
      [[ $# -ge 2 ]] || fail "--calendar requires a value"
      AUTO_UPDATE_CALENDAR="$2"
      shift 2
      ;;
    --systemd-user-dir)
      [[ $# -ge 2 ]] || fail "--systemd-user-dir requires a value"
      SYSTEMD_USER_DIR="$2"
      shift 2
      ;;
    --state-dir)
      [[ $# -ge 2 ]] || fail "--state-dir requires a value"
      AUTO_UPDATE_STATE_DIR="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    --offline)
      OFFLINE="true"
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

case "$COMMAND" in
  setup|skills)
    [[ -n "$PROFILE" ]] || fail "${COMMAND} requires --profile personal or --profile work"
    ;;
esac

if [[ "$STDOUT_ONLY" == "true" ]]; then
  [[ "$COMMAND" == "instructions" ]] || fail "--stdout is supported only by the instructions command"
  [[ -f "$INSTRUCTIONS_TEMPLATE" ]] || fail "missing instruction template: ${INSTRUCTIONS_TEMPLATE}"
  command cat "$INSTRUCTIONS_TEMPLATE"
  exit 0
fi

case "$COMMAND" in
  setup)
    preflight_instructions
    preflight_skills
    apply_instructions
    apply_skills
    ;;
  instructions)
    install_instructions
    ;;
  skills)
    install_skills
    ;;
  auto-update)
    [[ "$DRY_RUN" == "false" ]] || fail "--dry-run is not supported for auto-update management"
    manage_auto_update
    ;;
esac
