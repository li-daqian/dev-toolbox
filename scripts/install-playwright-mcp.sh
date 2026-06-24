#!/usr/bin/env bash
set -euo pipefail

TARGET="both"
SERVER_NAME="playwright"
PACKAGE_SPEC="@playwright/mcp@latest"
CLAUDE_SCOPE="user"
FORCE="false"
DRY_RUN="false"
ISOLATED="false"
NPX_YES="true"
SKIP_PACKAGE_CHECK="false"
BROWSER=""
PACKAGE_CHECKED="false"
CODEX_CHANGED="false"
CLAUDE_CHANGED="false"
TIMESTAMP="$(date +%Y%m%d%H%M%S)"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/install-playwright-mcp.sh [options]

Options:
  --target <codex|claude|both>     Install target. Default: both
  --server-name <name>             MCP server name. Default: playwright
  --package <npm-package-spec>     Playwright MCP npm package. Default: @playwright/mcp@latest
  --claude-scope <local|user|project>
                                    Claude Code MCP scope. Default: user
  --browser <chrome|firefox|webkit|msedge>
                                    Browser channel passed to Playwright MCP
  --isolated                       Use an isolated browser profile per MCP session
  --force                          Remove an existing server with the same name before adding
  --dry-run                        Print commands without changing configuration
  --no-npx-yes                     Do not pass -y to npx
  --skip-package-check             Skip npm registry package validation
  --help                           Show this help

Examples:
  ./scripts/install-playwright-mcp.sh
  ./scripts/install-playwright-mcp.sh --dry-run
  ./scripts/install-playwright-mcp.sh --force --isolated
  ./scripts/install-playwright-mcp.sh --browser chrome
EOF
}

log() {
  printf '%s\n' "$*"
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

quote_cmd() {
  local arg
  for arg in "$@"; do
    printf '%q ' "$arg"
  done
  printf '\n'
}

run_cmd() {
  printf '+ '
  quote_cmd "$@"
  if [[ "$DRY_RUN" == "false" ]]; then
    "$@"
  fi
}

require_command() {
  local command_name="$1"
  command_exists "$command_name" || fail "$command_name is required."
}

target_includes() {
  local candidate="$1"
  [[ "$TARGET" == "$candidate" || "$TARGET" == "both" ]]
}

backup_if_exists() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    return
  fi

  local backup_path="${path}.bak.${TIMESTAMP}"
  if [[ "$DRY_RUN" == "true" ]]; then
    log "Would back up ${path} to ${backup_path}"
    return
  fi

  cp "$path" "$backup_path"
  log "Backed up ${path} to ${backup_path}"
}

validate_node_version() {
  local version
  local major

  version="$(node -v)"
  version="${version#v}"
  major="${version%%.*}"

  [[ "$major" =~ ^[0-9]+$ ]] || fail "unable to parse Node.js version: ${version}"
  if (( major < 18 )); then
    fail "Node.js 18 or newer is required, found ${version}."
  fi
}

validate_package() {
  if [[ "$DRY_RUN" == "true" || "$SKIP_PACKAGE_CHECK" == "true" ]]; then
    return
  fi

  require_command npm
  log "Checking npm package ${PACKAGE_SPEC}..."
  npm view "$PACKAGE_SPEC" version >/dev/null
}

ensure_package_validated() {
  if [[ "$PACKAGE_CHECKED" == "true" ]]; then
    return
  fi

  validate_package
  PACKAGE_CHECKED="true"
}

build_mcp_command() {
  MCP_COMMAND=("npx")
  if [[ "$NPX_YES" == "true" ]]; then
    MCP_COMMAND+=("-y")
  fi
  MCP_COMMAND+=("$PACKAGE_SPEC")

  if [[ "$ISOLATED" == "true" ]]; then
    MCP_COMMAND+=("--isolated")
  fi

  if [[ -n "$BROWSER" ]]; then
    MCP_COMMAND+=("--browser" "$BROWSER")
  fi
}

codex_server_exists() {
  codex mcp get "$SERVER_NAME" --json >/dev/null 2>&1
}

claude_server_exists() {
  CLAUDE_MCP_SERVER_NAME="$SERVER_NAME" CLAUDE_MCP_PROJECT_DIR="$PWD" node <<'NODE'
const fs = require('fs');
const path = require('path');

const serverName = process.env.CLAUDE_MCP_SERVER_NAME;
const projectDir = process.env.CLAUDE_MCP_PROJECT_DIR || process.cwd();
const homeDir = process.env.HOME;

function readJsonIfExists(filePath) {
  if (!filePath || !fs.existsSync(filePath)) {
    return null;
  }

  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch (error) {
    console.error(`Error: unable to parse ${filePath}: ${error.message}`);
    process.exit(2);
  }
}

function hasServer(config) {
  return Boolean(config && config.mcpServers && config.mcpServers[serverName]);
}

const userConfig = readJsonIfExists(path.join(homeDir, '.claude.json'));
const projectConfig = readJsonIfExists(path.join(projectDir, '.mcp.json'));
const localProjectConfig = userConfig && userConfig.projects && userConfig.projects[projectDir];

const exists = hasServer(userConfig) || hasServer(projectConfig) || hasServer(localProjectConfig);
process.exit(exists ? 0 : 1);
NODE
}

install_codex() {
  local config_path="${CODEX_HOME:-${HOME}/.codex}/config.toml"

  if codex_server_exists; then
    if [[ "$FORCE" != "true" ]]; then
      log "Codex MCP server '${SERVER_NAME}' already exists; use --force to replace it."
      return
    fi

    ensure_package_validated
    backup_if_exists "$config_path"
    run_cmd codex mcp remove "$SERVER_NAME"
  else
    ensure_package_validated
    backup_if_exists "$config_path"
  fi

  run_cmd codex mcp add "$SERVER_NAME" -- "${MCP_COMMAND[@]}"
  CODEX_CHANGED="true"
}

install_claude() {
  local config_path="${HOME}/.claude.json"

  if claude_server_exists; then
    if [[ "$FORCE" != "true" ]]; then
      log "Claude Code MCP server '${SERVER_NAME}' already exists; use --force to replace it."
      return
    fi

    ensure_package_validated
    backup_if_exists "$config_path"
    run_cmd claude mcp remove "$SERVER_NAME"
  else
    ensure_package_validated
    backup_if_exists "$config_path"
  fi

  run_cmd claude mcp add --scope "$CLAUDE_SCOPE" --transport stdio "$SERVER_NAME" -- "${MCP_COMMAND[@]}"
  CLAUDE_CHANGED="true"
}

verify_installation() {
  if [[ "$DRY_RUN" == "true" ]]; then
    log "Dry-run complete; no MCP configuration was changed."
    return
  fi

  if [[ "$CODEX_CHANGED" == "true" ]]; then
    run_cmd codex mcp get "$SERVER_NAME" --json
  fi

  if [[ "$CLAUDE_CHANGED" == "true" ]]; then
    run_cmd claude mcp get "$SERVER_NAME"
  fi

  if [[ "$CODEX_CHANGED" == "true" || "$CLAUDE_CHANGED" == "true" ]]; then
    log "Restart Codex and Claude Code sessions, then run /mcp to check connection status."
  else
    log "No MCP configuration was changed."
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      [[ $# -ge 2 ]] || fail "--target requires a value"
      TARGET="$2"
      shift 2
      ;;
    --server-name)
      [[ $# -ge 2 ]] || fail "--server-name requires a value"
      SERVER_NAME="$2"
      shift 2
      ;;
    --package)
      [[ $# -ge 2 ]] || fail "--package requires a value"
      PACKAGE_SPEC="$2"
      shift 2
      ;;
    --claude-scope)
      [[ $# -ge 2 ]] || fail "--claude-scope requires a value"
      CLAUDE_SCOPE="$2"
      shift 2
      ;;
    --browser)
      [[ $# -ge 2 ]] || fail "--browser requires a value"
      BROWSER="$2"
      shift 2
      ;;
    --isolated)
      ISOLATED="true"
      shift
      ;;
    --force)
      FORCE="true"
      shift
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    --no-npx-yes)
      NPX_YES="false"
      shift
      ;;
    --skip-package-check)
      SKIP_PACKAGE_CHECK="true"
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

case "$TARGET" in
  codex|claude|both)
    ;;
  *)
    fail "target must be one of: codex, claude, both"
    ;;
esac

case "$CLAUDE_SCOPE" in
  local|user|project)
    ;;
  *)
    fail "claude scope must be one of: local, user, project"
    ;;
esac

case "$BROWSER" in
  ""|chrome|firefox|webkit|msedge)
    ;;
  *)
    fail "browser must be one of: chrome, firefox, webkit, msedge"
    ;;
esac

if [[ -z "$SERVER_NAME" ]]; then
  fail "server name cannot be empty"
fi

require_command node
require_command npx
validate_node_version
build_mcp_command

if target_includes codex; then
  require_command codex
  install_codex
fi

if target_includes claude; then
  require_command claude
  install_claude
fi

verify_installation
