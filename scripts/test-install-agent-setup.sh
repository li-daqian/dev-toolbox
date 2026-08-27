#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd -P)"
INSTALLER="${SCRIPT_DIR}/install-agent-setup.sh"
LEGACY_CHARTER="${SCRIPT_DIR}/install-global-agent-charter.sh"
LEGACY_SKILLS="${SCRIPT_DIR}/install-matt-pocock-skills.sh"
TEST_ROOT="$(mktemp -d)"
SOURCE_DIR="${TEST_ROOT}/source"
CODEX_USER_DIR="${TEST_ROOT}/codex-user-skills"
CLAUDE_USER_DIR="${TEST_ROOT}/claude-user-skills"
PROJECT_DIR="${TEST_ROOT}/project"

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

assert_managed_entry() {
  local path="$1"
  assert_exists "$path"
  if [[ ! -L "$path" ]]; then
    assert_file_contains "$path/.dev-toolbox-agent-setup" 'provider=mattpocock'
  fi
}

create_source_fixture() {
  local target_source_dir="${1:-$SOURCE_DIR}"
  local fixture_manifest_root="${2:-$REPO_ROOT/agent/skills}"
  local manifest
  local relative_path
  local skill_name

  mkdir -p "$target_source_dir"
  for manifest in \
    "$fixture_manifest_root/mattpocock-personal.txt" \
    "$fixture_manifest_root/mattpocock-work.txt"; do
    while IFS= read -r relative_path || [[ -n "$relative_path" ]]; do
      relative_path="${relative_path%$'\r'}"
      case "$relative_path" in ''|'#'*) continue ;; esac
      skill_name="$(basename "$relative_path")"
      mkdir -p "$target_source_dir/$relative_path"
      printf '%s\n' '---' "name: ${skill_name}" 'description: test fixture' '---' \
        > "$target_source_dir/$relative_path/SKILL.md"
      printf 'resource for %s\n' "$skill_name" > "$target_source_dir/$relative_path/resource.txt"
    done < "$manifest"
  done
}

run_skills() {
  bash "$INSTALLER" skills "$@" \
    --source-dir "$SOURCE_DIR" \
    --codex-user-skills-dir "$CODEX_USER_DIR" \
    --claude-user-skills-dir "$CLAUDE_USER_DIR"
}

create_source_fixture "$SOURCE_DIR" "$REPO_ROOT/agent/skills"

# A Windows-style CRLF checkout must create fixture paths without a trailing CR.
CRLF_MANIFEST_ROOT="$TEST_ROOT/crlf-manifests"
CRLF_SOURCE_DIR="$TEST_ROOT/crlf-source"
mkdir -p "$CRLF_MANIFEST_ROOT"
awk '{ printf "%s\r\n", $0 }' "$REPO_ROOT/agent/skills/mattpocock-personal.txt" \
  > "$CRLF_MANIFEST_ROOT/mattpocock-personal.txt"
awk '{ printf "%s\r\n", $0 }' "$REPO_ROOT/agent/skills/mattpocock-work.txt" \
  > "$CRLF_MANIFEST_ROOT/mattpocock-work.txt"
create_source_fixture "$CRLF_SOURCE_DIR" "$CRLF_MANIFEST_ROOT"
assert_exists "$CRLF_SOURCE_DIR/skills/engineering/ask-matt/SKILL.md"
mkdir -p "$PROJECT_DIR"
git -C "$PROJECT_DIR" init -q

personal_count="$(grep -Ev '^[[:space:]]*(#|$)' "$REPO_ROOT/agent/skills/mattpocock-personal.txt" | wc -l | tr -d ' ')"
work_count="$(grep -Ev '^[[:space:]]*(#|$)' "$REPO_ROOT/agent/skills/mattpocock-work.txt" | wc -l | tr -d ' ')"
[[ "$personal_count" == "25" ]] || fail_test "personal manifest should contain 25 skills"
[[ "$work_count" == "3" ]] || fail_test "work manifest should contain 3 skills"

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

# User scope installs both Agents, then reconciles personal down to work.
run_skills --profile personal --scope user --agent both >/dev/null
assert_managed_entry "$CODEX_USER_DIR/ask-matt"
assert_managed_entry "$CLAUDE_USER_DIR/writing-for-agents"
assert_absent "$CODEX_USER_DIR/git-guardrails-claude-code"

run_skills --profile work --scope user --agent both >/dev/null
for skill_name in grilling grill-me diagnosing-bugs; do
  assert_managed_entry "$CODEX_USER_DIR/$skill_name"
  assert_managed_entry "$CLAUDE_USER_DIR/$skill_name"
done
assert_absent "$CODEX_USER_DIR/ask-matt"
assert_absent "$CLAUDE_USER_DIR/domain-modeling"

# Project scope reuses exact user-scope entries and installs the remainder at Git root.
run_skills --profile personal --scope project --agent both --project "$PROJECT_DIR" >/dev/null
assert_absent "$PROJECT_DIR/.agents/skills/grilling"
assert_absent "$PROJECT_DIR/.claude/skills/grilling"
assert_managed_entry "$PROJECT_DIR/.agents/skills/ask-matt"
assert_managed_entry "$PROJECT_DIR/.claude/skills/ask-matt"

# A different user-scope implementation must block project installation.
mkdir -p "$CODEX_USER_DIR/teach"
printf '%s\n' 'unknown implementation' > "$CODEX_USER_DIR/teach/SKILL.md"
if run_skills --profile personal --scope project --agent codex --project "$PROJECT_DIR" >/dev/null 2>&1; then
  fail_test "expected a different user-scope skill to block project installation"
fi
rm -rf -- "$CODEX_USER_DIR/teach"

# Cross-Agent preflight prevents partial instruction or skill writes.
ATOMIC_CODEX_SKILLS="$TEST_ROOT/atomic-codex-skills"
ATOMIC_CLAUDE_SKILLS="$TEST_ROOT/atomic-claude-skills"
ATOMIC_CODEX_PATH="$TEST_ROOT/atomic-codex/AGENTS.md"
ATOMIC_CLAUDE_PATH="$TEST_ROOT/atomic-claude/CLAUDE.md"
mkdir -p "$ATOMIC_CLAUDE_SKILLS/grilling"
printf '%s\n' 'unmanaged' > "$ATOMIC_CLAUDE_SKILLS/grilling/SKILL.md"
if bash "$INSTALLER" setup --profile work --scope user --agent both \
  --source-dir "$SOURCE_DIR" \
  --codex-user-skills-dir "$ATOMIC_CODEX_SKILLS" \
  --claude-user-skills-dir "$ATOMIC_CLAUDE_SKILLS" \
  --codex-path "$ATOMIC_CODEX_PATH" \
  --claude-path "$ATOMIC_CLAUDE_PATH" >/dev/null 2>&1; then
  fail_test "expected cross-Agent collision to fail"
fi
assert_absent "$ATOMIC_CODEX_SKILLS/grilling"
assert_absent "$ATOMIC_CODEX_PATH"
assert_absent "$ATOMIC_CLAUDE_PATH"

# Windows Git Bash mode uses refreshable managed copies.
COPY_CODEX_DIR="$TEST_ROOT/copy-codex-skills"
AGENT_SETUP_PLATFORM=windows-git-bash bash "$INSTALLER" skills \
  --profile work --scope user --agent codex \
  --source-dir "$SOURCE_DIR" \
  --codex-user-skills-dir "$COPY_CODEX_DIR" >/dev/null
assert_managed_entry "$COPY_CODEX_DIR/grilling"
[[ ! -L "$COPY_CODEX_DIR/grilling" ]] || fail_test "Git Bash mode should use a copy"
assert_file_contains "$COPY_CODEX_DIR/grilling/resource.txt" 'resource for grilling'
printf '%s\n' 'updated resource' > "$SOURCE_DIR/skills/productivity/grilling/resource.txt"
AGENT_SETUP_PLATFORM=windows-git-bash bash "$INSTALLER" skills \
  --profile work --scope user --agent codex \
  --source-dir "$SOURCE_DIR" \
  --codex-user-skills-dir "$COPY_CODEX_DIR" >/dev/null
assert_file_contains "$COPY_CODEX_DIR/grilling/resource.txt" 'updated resource'

# Strict offline and dry-run behavior.
if bash "$INSTALLER" skills --profile work --offline \
  --source-root "$TEST_ROOT/missing-source" \
  --codex-user-skills-dir "$TEST_ROOT/offline-target" >/dev/null 2>&1; then
  fail_test "offline mode should require an existing checkout"
fi
bash "$INSTALLER" skills --profile work --dry-run \
  --source-root "$TEST_ROOT/dry-run-source" \
  --codex-user-skills-dir "$TEST_ROOT/dry-run-target" >/dev/null 2>&1
assert_absent "$TEST_ROOT/dry-run-source"
assert_absent "$TEST_ROOT/dry-run-target"

# Legacy wrappers preserve charter preview/apply and old skill profile mappings.
LEGACY_CODEX_PATH="$TEST_ROOT/legacy-codex/AGENTS.md"
bash "$LEGACY_CHARTER" --target codex --codex-path "$LEGACY_CODEX_PATH" >/dev/null
assert_absent "$LEGACY_CODEX_PATH"
bash "$LEGACY_CHARTER" --target codex --apply --codex-path "$LEGACY_CODEX_PATH" >/dev/null
assert_exists "$LEGACY_CODEX_PATH"

LEGACY_USER_DIR="$TEST_ROOT/legacy-user-skills"
bash "$LEGACY_SKILLS" work --source-dir "$SOURCE_DIR" --user-skills-dir "$LEGACY_USER_DIR" >/dev/null
assert_managed_entry "$LEGACY_USER_DIR/grilling"
assert_absent "$LEGACY_USER_DIR/domain-modeling"

LEGACY_PROJECT_DIR="$TEST_ROOT/legacy-project"
mkdir -p "$LEGACY_PROJECT_DIR"
git -C "$LEGACY_PROJECT_DIR" init -q
bash "$LEGACY_SKILLS" personal \
  --source-dir "$SOURCE_DIR" \
  --user-skills-dir "$TEST_ROOT/legacy-personal-user-skills" \
  --project "$LEGACY_PROJECT_DIR" >/dev/null
assert_managed_entry "$LEGACY_PROJECT_DIR/.agents/skills/ask-matt"
assert_absent "$LEGACY_PROJECT_DIR/.agents/skills/git-guardrails-claude-code"

# New systemd units serialize profile/Agent and migrate legacy unit files.
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
    printf '%s\n' legacy > "$SYSTEMD_USER_DIR/codex-matt-pocock-skills-update.service"
    printf '%s\n' legacy > "$SYSTEMD_USER_DIR/codex-matt-pocock-skills-update.timer"

    PATH="$FAKE_BIN:$PATH" SYSTEMCTL_LOG="$SYSTEMCTL_LOG" \
      bash "$INSTALLER" auto-update enable \
        --profile work --agent both \
        --source-root "$SOURCE_DIR" \
        --calendar 'Tue *-*-* 10:30:00' \
        --systemd-user-dir "$SYSTEMD_USER_DIR" \
        --state-dir "$UPDATER_STATE_DIR" >/dev/null

    SERVICE_PATH="$SYSTEMD_USER_DIR/agent-setup-skills-update.service"
    TIMER_PATH="$SYSTEMD_USER_DIR/agent-setup-skills-update.timer"
    assert_file_contains "$SERVICE_PATH" '--profile "work"'
    assert_file_contains "$SERVICE_PATH" '--agent "both"'
    assert_file_contains "$TIMER_PATH" 'OnCalendar=Tue *-*-* 10:30:00'
    assert_absent "$SYSTEMD_USER_DIR/codex-matt-pocock-skills-update.service"
    assert_absent "$SYSTEMD_USER_DIR/codex-matt-pocock-skills-update.timer"
    assert_file_contains "$SYSTEMCTL_LOG" '--user disable --now codex-matt-pocock-skills-update.timer'

    PATH="$FAKE_BIN:$PATH" SYSTEMCTL_LOG="$SYSTEMCTL_LOG" \
      bash "$INSTALLER" auto-update disable \
        --systemd-user-dir "$SYSTEMD_USER_DIR" \
        --state-dir "$UPDATER_STATE_DIR" >/dev/null
    assert_absent "$SERVICE_PATH"
    assert_absent "$TIMER_PATH"
    ;;
  *)
    if bash "$INSTALLER" auto-update enable --profile work >/dev/null 2>&1; then
      fail_test "auto-update should be rejected outside Linux/systemd WSL"
    fi
    ;;
esac

printf 'PASS: Agent setup profiles, scopes, Agents, platforms, safety, wrappers, and updater\n'
