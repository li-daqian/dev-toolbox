#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd -P)"
INSTALLER="${SCRIPT_DIR}/install-agent-setup.sh"
LEGACY_CHARTER="${SCRIPT_DIR}/install-global-agent-charter.sh"
TEST_ROOT="$(mktemp -d)"
CODEX_USER_DIR="${TEST_ROOT}/codex-user-skills"
CLAUDE_USER_DIR="${TEST_ROOT}/claude-user-skills"
PROJECT_DIR="${TEST_ROOT}/project"

cleanup() {
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

# Exercise dependency installation without network access or real user writes.
(
  source "$SCRIPT_DIR/lib/agent-setup/common.sh"
  source "$SCRIPT_DIR/lib/agent-setup/skills.sh"
  export HOME="$TEST_ROOT/dependency-home"
  PLATFORM=linux
  DRY_RUN=true
  OFFLINE=false
  command_exists() {
    [[ "$1" != "yt-dlp" ]] && command -v "$1" >/dev/null 2>&1
  }
  curl() {
    printf '%s\n' "$*" >> "$TEST_ROOT/downloads.log"
    while [[ "$1" != "-o" ]]; do shift; done
    printf '#!/usr/bin/env bash\nprintf "test-version\\n"\n' > "$2"
  }
  install_last30days_ytdlp >/dev/null || exit 1
  [[ ! -e "$HOME/.local/bin" ]] || exit 1
  DRY_RUN=false
  OFFLINE=true
  if install_last30days_ytdlp >/dev/null 2>&1; then
    exit 1
  fi
  [[ ! -f "$TEST_ROOT/downloads.log" ]] || exit 1
  OFFLINE=false
  install_last30days_ytdlp >/dev/null 2>&1 || exit 1
  [[ "$("$HOME/.local/bin/yt-dlp" --version)" == test-version ]] || exit 1
  OFFLINE=true
  install_last30days_ytdlp >/dev/null 2>&1 || exit 1
  [[ "$(wc -l < "$TEST_ROOT/downloads.log" | tr -d ' ')" == 1 ]] || exit 1
) || { printf 'FAIL: yt-dlp dependency installation\n' >&2; exit 1; }

# The remaining installer tests reuse an installed dependency.
mkdir -p "$TEST_ROOT/dependency-bin"
printf '#!/usr/bin/env bash\nprintf "test-version\\n"\n' > "$TEST_ROOT/dependency-bin/yt-dlp"
chmod +x "$TEST_ROOT/dependency-bin/yt-dlp"
export PATH="$TEST_ROOT/dependency-bin:$PATH"

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

assert_managed_entry() {
  local path="$1"
  assert_exists "$path"
  if [[ ! -L "$path" ]]; then
    assert_file_contains "$path/.dev-toolbox-agent-setup" 'provider=last30days'
  fi
}

run_skills() {
  bash "$INSTALLER" skills \
    --codex-user-skills-dir "$CODEX_USER_DIR" \
    --claude-user-skills-dir "$CLAUDE_USER_DIR" "$@"
}

LAST30DAYS_FIXTURE="$TEST_ROOT/last30days-source"
export AGENT_SETUP_LAST30DAYS_SOURCE_DIR="$LAST30DAYS_FIXTURE"
mkdir -p "$LAST30DAYS_FIXTURE/skills/last30days/scripts"
printf '%s\n' '---' 'name: last30days' 'description: test fixture' '---' > "$LAST30DAYS_FIXTURE/skills/last30days/SKILL.md"
printf '%s\n' 'engine resource' > "$LAST30DAYS_FIXTURE/skills/last30days/scripts/resource.txt"
mkdir -p "$PROJECT_DIR"
git -C "$PROJECT_DIR" init -q

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

# User scope installs both Agents and preserves full skill resources.
run_skills --scope user --agent both >/dev/null
assert_managed_entry "$CODEX_USER_DIR/last30days"
assert_managed_entry "$CLAUDE_USER_DIR/last30days"
assert_exists "$CODEX_USER_DIR/last30days/scripts/resource.txt"
run_skills --scope user --agent both >/dev/null

# Project scope reuses exact user-scope entries.
run_skills --scope project --agent both --project "$PROJECT_DIR" >/dev/null
assert_absent "$PROJECT_DIR/.agents/skills/last30days"
assert_absent "$PROJECT_DIR/.claude/skills/last30days"
run_skills --scope project --agent codex --project "$PROJECT_DIR" \
  --codex-user-skills-dir "$TEST_ROOT/empty-user" >/dev/null
assert_managed_entry "$PROJECT_DIR/.agents/skills/last30days"

# A different user-scope implementation must block project installation.
CONFLICT_USER_DIR="$TEST_ROOT/conflict-user"
mkdir -p "$CONFLICT_USER_DIR/last30days"
printf '%s\n' 'unknown implementation' > "$CONFLICT_USER_DIR/last30days/SKILL.md"
if run_skills --scope project --agent codex --project "$PROJECT_DIR" \
  --codex-user-skills-dir "$CONFLICT_USER_DIR" >/dev/null 2>&1; then
  fail_test "expected a different user-scope skill to block project installation"
fi

# Cross-Agent preflight prevents partial instruction or skill writes.
ATOMIC_CODEX_SKILLS="$TEST_ROOT/atomic-codex-skills"
ATOMIC_CLAUDE_SKILLS="$TEST_ROOT/atomic-claude-skills"
ATOMIC_CODEX_PATH="$TEST_ROOT/atomic-codex/AGENTS.md"
ATOMIC_CLAUDE_PATH="$TEST_ROOT/atomic-claude/CLAUDE.md"
mkdir -p "$ATOMIC_CLAUDE_SKILLS/last30days"
printf '%s\n' 'unmanaged' > "$ATOMIC_CLAUDE_SKILLS/last30days/SKILL.md"
if bash "$INSTALLER" setup --scope user --agent both \
  --codex-user-skills-dir "$ATOMIC_CODEX_SKILLS" \
  --claude-user-skills-dir "$ATOMIC_CLAUDE_SKILLS" \
  --codex-path "$ATOMIC_CODEX_PATH" \
  --claude-path "$ATOMIC_CLAUDE_PATH" >/dev/null 2>&1; then
  fail_test "expected cross-Agent collision to fail"
fi
assert_absent "$ATOMIC_CODEX_SKILLS/last30days"
assert_absent "$ATOMIC_CODEX_PATH"
assert_absent "$ATOMIC_CLAUDE_PATH"

# Windows Git Bash mode uses refreshable managed copies.
COPY_CODEX_DIR="$TEST_ROOT/copy-codex-skills"
AGENT_SETUP_PLATFORM=windows-git-bash bash "$INSTALLER" skills \
  --scope user --agent codex \
  --codex-user-skills-dir "$COPY_CODEX_DIR" >/dev/null
assert_managed_entry "$COPY_CODEX_DIR/last30days"
[[ ! -L "$COPY_CODEX_DIR/last30days" ]] || fail_test "Git Bash mode should use a copy"
assert_file_contains "$COPY_CODEX_DIR/last30days/scripts/resource.txt" 'engine resource'
printf '%s\n' 'updated resource' > "$LAST30DAYS_FIXTURE/skills/last30days/scripts/resource.txt"
AGENT_SETUP_PLATFORM=windows-git-bash bash "$INSTALLER" skills \
  --scope user --agent codex \
  --codex-user-skills-dir "$COPY_CODEX_DIR" >/dev/null
assert_file_contains "$COPY_CODEX_DIR/last30days/scripts/resource.txt" 'updated resource'

# Strict offline and dry-run behavior.
if AGENT_SETUP_LAST30DAYS_SOURCE_DIR= bash "$INSTALLER" skills --offline \
  --last30days-source-root "$TEST_ROOT/missing-source" \
  --codex-user-skills-dir "$TEST_ROOT/offline-target" >/dev/null 2>&1; then
  fail_test "offline mode should require an existing checkout"
fi
AGENT_SETUP_LAST30DAYS_SOURCE_DIR= bash "$INSTALLER" skills --dry-run \
  --last30days-source-root "$TEST_ROOT/dry-run-source" \
  --codex-user-skills-dir "$TEST_ROOT/dry-run-target" >/dev/null 2>&1
assert_absent "$TEST_ROOT/dry-run-source"
assert_absent "$TEST_ROOT/dry-run-target"

# The charter wrapper preserves preview/apply.
LEGACY_CODEX_PATH="$TEST_ROOT/legacy-codex/AGENTS.md"
bash "$LEGACY_CHARTER" --target codex --codex-path "$LEGACY_CODEX_PATH" >/dev/null
assert_absent "$LEGACY_CODEX_PATH"
bash "$LEGACY_CHARTER" --target codex --apply --codex-path "$LEGACY_CODEX_PATH" >/dev/null
assert_exists "$LEGACY_CODEX_PATH"

# last30days preserves all bundled runtime resources.
assert_exists "$CODEX_USER_DIR/last30days/scripts/resource.txt"
assert_file_contains "$COPY_CODEX_DIR/last30days/.dev-toolbox-agent-setup" 'provider=last30days'
LAST30DAYS_CONFLICT="$TEST_ROOT/last30days-conflict"
mkdir -p "$LAST30DAYS_CONFLICT/last30days"
printf '%s\n' 'unmanaged' > "$LAST30DAYS_CONFLICT/last30days/SKILL.md"
if bash "$INSTALLER" skills --agent codex \
  --codex-user-skills-dir "$LAST30DAYS_CONFLICT" >/dev/null 2>&1; then
  fail_test "unmanaged last30days must block installation"
fi
assert_file_contains "$LAST30DAYS_CONFLICT/last30days/SKILL.md" 'unmanaged'
bash "$INSTALLER" skills --agent codex \
  --last30days-source-dir "$LAST30DAYS_FIXTURE" --dry-run \
  --codex-user-skills-dir "$TEST_ROOT/last30days-dry-run" >/dev/null
assert_absent "$TEST_ROOT/last30days-dry-run"
unset AGENT_SETUP_LAST30DAYS_SOURCE_DIR

# systemd units serialize only the last30days source and Agent target.
# Positive scheduler coverage runs on Linux; other matrix jobs verify rejection.
case "$(uname -s 2>/dev/null || printf unknown)" in
  Linux)
    FAKE_BIN="$TEST_ROOT/bin"
    SYSTEMCTL_LOG="$TEST_ROOT/systemctl.log"
    SYSTEMD_USER_DIR="$TEST_ROOT/systemd-user"
    UPDATER_STATE_DIR="$TEST_ROOT/updater-state"
    mkdir -p "$FAKE_BIN" "$SYSTEMD_USER_DIR"
    printf '%s\n' \
      '#!/usr/bin/env bash' \
      'printf "%s\n" "$*" >> "${SYSTEMCTL_LOG:?}"' \
      > "$FAKE_BIN/systemctl"
    chmod +x "$FAKE_BIN/systemctl"

    PATH="$FAKE_BIN:$PATH" SYSTEMCTL_LOG="$SYSTEMCTL_LOG" \
      bash "$INSTALLER" auto-update enable \
        --agent both \
        --last30days-ref v3.30.0 --last30days-source-root "$LAST30DAYS_FIXTURE" \
        --calendar 'Tue *-*-* 10:30:00' \
        --systemd-user-dir "$SYSTEMD_USER_DIR" \
        --state-dir "$UPDATER_STATE_DIR" >/dev/null

    SERVICE_PATH="$SYSTEMD_USER_DIR/agent-setup-skills-update.service"
    TIMER_PATH="$SYSTEMD_USER_DIR/agent-setup-skills-update.timer"
    assert_file_contains "$SERVICE_PATH" '--agent "both"'
    assert_file_contains "$SERVICE_PATH" '--last30days-ref "v3.30.0"'
    assert_file_contains "$SERVICE_PATH" "--last30days-source-root \"$LAST30DAYS_FIXTURE\""
    assert_file_contains "$TIMER_PATH" 'OnCalendar=Tue *-*-* 10:30:00'

    PATH="$FAKE_BIN:$PATH" SYSTEMCTL_LOG="$SYSTEMCTL_LOG" \
      bash "$INSTALLER" auto-update disable \
        --systemd-user-dir "$SYSTEMD_USER_DIR" \
        --state-dir "$UPDATER_STATE_DIR" >/dev/null
    assert_absent "$SERVICE_PATH"
    assert_absent "$TIMER_PATH"
    ;;
  *)
    if bash "$INSTALLER" auto-update enable >/dev/null 2>&1; then
      fail_test "auto-update should be rejected outside Linux/systemd WSL"
    fi
    ;;
esac

printf 'PASS: Agent setup instructions, last30days, scopes, Agents, platforms, safety, wrapper, and updater\n'
