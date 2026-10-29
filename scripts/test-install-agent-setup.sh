#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd -P)"
INSTALLER="${SCRIPT_DIR}/install-agent-setup.sh"
LEGACY_CHARTER="${SCRIPT_DIR}/install-global-agent-charter.sh"
TEST_ROOT="$(mktemp -d)"

cleanup() {
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

fail_test() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_exists() {
  [[ -e "$1" || -L "$1" ]] || fail_test "expected path: $1"
}

assert_absent() {
  [[ ! -e "$1" && ! -L "$1" ]] || fail_test "expected path to be absent: $1"
}

assert_file_contains() {
  local file_path="$1"
  local expected="$2"
  [[ -f "$file_path" ]] || fail_test "expected file: ${file_path}"
  grep -Fq -- "$expected" "$file_path" || fail_test "expected ${file_path} to contain: ${expected}"
}

bash "$INSTALLER" --help >/dev/null
bash "$INSTALLER" instructions --stdout | cmp - "$REPO_ROOT/agent/global-instructions.md"

# Instructions: dry-run, apply, idempotency, backup, and override warning.
CODEX_PATH="$TEST_ROOT/codex/AGENTS.md"
CLAUDE_PATH="$TEST_ROOT/claude/CLAUDE.md"
bash "$INSTALLER" instructions --agent both --dry-run \
  --codex-path "$CODEX_PATH" --claude-path "$CLAUDE_PATH" >/dev/null
assert_absent "$CODEX_PATH"
assert_absent "$CLAUDE_PATH"

bash "$INSTALLER" instructions --agent both \
  --codex-path "$CODEX_PATH" --claude-path "$CLAUDE_PATH" >/dev/null
cmp "$CODEX_PATH" "$REPO_ROOT/agent/global-instructions.md"
cmp "$CLAUDE_PATH" "$REPO_ROOT/agent/global-instructions.md"

bash "$INSTALLER" instructions --agent codex --codex-path "$CODEX_PATH" >/dev/null
backup_count="$(find "$(dirname "$CODEX_PATH")" -maxdepth 1 -name 'AGENTS.md.bak.*' | wc -l | tr -d ' ')"
[[ "$backup_count" == "0" ]] || fail_test "idempotent instruction install created a backup"
printf '%s\n' 'local content' > "$CODEX_PATH"
bash "$INSTALLER" instructions --agent codex --codex-path "$CODEX_PATH" >/dev/null
backup_count="$(find "$(dirname "$CODEX_PATH")" -maxdepth 1 -name 'AGENTS.md.bak.*' | wc -l | tr -d ' ')"
[[ "$backup_count" == "1" ]] || fail_test "changed instructions should create one backup"

printf '%s\n' 'override' > "$(dirname "$CODEX_PATH")/AGENTS.override.md"
bash "$INSTALLER" instructions --agent codex --codex-path "$CODEX_PATH" \
  >"$TEST_ROOT/override.out" 2>"$TEST_ROOT/override.err"
assert_file_contains "$TEST_ROOT/override.err" 'masks'

case "$(uname -s 2>/dev/null || printf unknown)" in
  MINGW*|MSYS*|CYGWIN*) ;;
  *)
    LINK_TARGET="$TEST_ROOT/instruction-link-target.md"
    LINK_PATH="$TEST_ROOT/instruction-link/AGENTS.md"
    mkdir -p "$(dirname "$LINK_PATH")"
    printf '%s\n' 'must stay unchanged' > "$LINK_TARGET"
    ln -s "$LINK_TARGET" "$LINK_PATH"
    if bash "$INSTALLER" instructions --agent codex --codex-path "$LINK_PATH" >/dev/null 2>&1; then
      fail_test "instruction symlink should be rejected"
    fi
    assert_file_contains "$LINK_TARGET" 'must stay unchanged'
    ;;
esac

# setup now writes only instructions and preflights both Agents before writing.
SETUP_CODEX_PATH="$TEST_ROOT/setup-codex/AGENTS.md"
SETUP_CLAUDE_PATH="$TEST_ROOT/setup-claude/CLAUDE.md"
mkdir -p "$SETUP_CLAUDE_PATH"
if bash "$INSTALLER" setup --agent both \
  --codex-path "$SETUP_CODEX_PATH" --claude-path "$SETUP_CLAUDE_PATH" >/dev/null 2>&1; then
  fail_test "expected non-regular instruction destination to fail"
fi
assert_absent "$SETUP_CODEX_PATH"
rmdir "$SETUP_CLAUDE_PATH"
bash "$INSTALLER" setup --agent both \
  --codex-path "$SETUP_CODEX_PATH" --claude-path "$SETUP_CLAUDE_PATH" >/dev/null
cmp "$SETUP_CODEX_PATH" "$REPO_ROOT/agent/global-instructions.md"
cmp "$SETUP_CLAUDE_PATH" "$REPO_ROOT/agent/global-instructions.md"

# The charter wrapper preserves preview/apply.
LEGACY_CODEX_PATH="$TEST_ROOT/legacy-codex/AGENTS.md"
bash "$LEGACY_CHARTER" --target codex --codex-path "$LEGACY_CODEX_PATH" >/dev/null
assert_absent "$LEGACY_CODEX_PATH"
bash "$LEGACY_CHARTER" --target codex --apply --codex-path "$LEGACY_CODEX_PATH" >/dev/null
assert_exists "$LEGACY_CODEX_PATH"

printf 'PASS: Agent global instructions, dry-run, idempotency, backups, safety, and wrapper\n'
