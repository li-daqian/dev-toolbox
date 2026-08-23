#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
INSTALLER="${SCRIPT_DIR}/install-matt-pocock-skills.sh"
TEST_ROOT="$(mktemp -d)"
SOURCE_DIR="${TEST_ROOT}/source"
USER_SKILLS_DIR="${TEST_ROOT}/user-skills"
PROJECT_DIR="${TEST_ROOT}/personal-project"

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

create_skill() {
  local relative_path="$1"
  local skill_name

  skill_name="$(basename "$relative_path")"
  mkdir -p "$SOURCE_DIR/$relative_path"
  printf '%s\n' '---' "name: ${skill_name}" 'description: test fixture' '---' \
    > "$SOURCE_DIR/$relative_path/SKILL.md"
}

assert_symlink_to() {
  local link_path="$1"
  local expected_path="$2"

  [[ -L "$link_path" ]] || fail "expected symlink: ${link_path}"
  [[ "$(readlink -f "$link_path")" == "$(readlink -f "$expected_path")" ]] ||
    fail "unexpected target for ${link_path}"
}

assert_absent() {
  [[ ! -e "$1" && ! -L "$1" ]] || fail "expected path to be absent: $1"
}

for relative_path in \
  skills/productivity/grilling \
  skills/productivity/grill-me \
  skills/engineering/diagnosing-bugs \
  skills/engineering/domain-modeling \
  skills/engineering/grill-with-docs \
  skills/engineering/tdd \
  skills/productivity/teach \
  skills/misc/setup-pre-commit \
  skills/in-progress/experimental-skill \
  skills/deprecated/legacy-skill; do
  create_skill "$relative_path"
done

"$INSTALLER" --help >/dev/null

"$INSTALLER" work --source-dir "$SOURCE_DIR" --user-skills-dir "$USER_SKILLS_DIR"

for skill_name in grilling grill-me diagnosing-bugs domain-modeling grill-with-docs; do
  case "$skill_name" in
    grilling|grill-me)
      bucket="productivity"
      ;;
    *)
      bucket="engineering"
      ;;
  esac
  assert_symlink_to "$USER_SKILLS_DIR/$skill_name" "$SOURCE_DIR/skills/$bucket/$skill_name"
done
assert_absent "$USER_SKILLS_DIR/tdd"

# Re-running the work profile must be idempotent.
"$INSTALLER" work --source-dir "$SOURCE_DIR" --user-skills-dir "$USER_SKILLS_DIR" >/dev/null

mkdir -p "$PROJECT_DIR"
git -C "$PROJECT_DIR" init -q
"$INSTALLER" personal \
  --source-dir "$SOURCE_DIR" \
  --user-skills-dir "$USER_SKILLS_DIR" \
  --project "$PROJECT_DIR"

PROJECT_SKILLS_DIR="$PROJECT_DIR/.agents/skills"
for skill_name in grilling grill-me diagnosing-bugs domain-modeling grill-with-docs; do
  assert_absent "$PROJECT_SKILLS_DIR/$skill_name"
done
assert_symlink_to "$PROJECT_SKILLS_DIR/tdd" "$SOURCE_DIR/skills/engineering/tdd"
assert_symlink_to "$PROJECT_SKILLS_DIR/teach" "$SOURCE_DIR/skills/productivity/teach"
assert_symlink_to "$PROJECT_SKILLS_DIR/setup-pre-commit" "$SOURCE_DIR/skills/misc/setup-pre-commit"
assert_absent "$PROJECT_SKILLS_DIR/experimental-skill"
assert_absent "$PROJECT_SKILLS_DIR/legacy-skill"

# A non-managed collision must fail without being overwritten.
rm "$PROJECT_SKILLS_DIR/tdd"
mkdir "$PROJECT_SKILLS_DIR/tdd"
if "$INSTALLER" personal \
  --source-dir "$SOURCE_DIR" \
  --user-skills-dir "$USER_SKILLS_DIR" \
  --project "$PROJECT_DIR" >/dev/null 2>&1; then
  fail "expected a non-managed destination collision to fail"
fi
[[ -d "$PROJECT_SKILLS_DIR/tdd" && ! -L "$PROJECT_SKILLS_DIR/tdd" ]] ||
  fail "collision path was unexpectedly replaced"

# A broken user-scope link must not silently hide a project skill.
rmdir "$PROJECT_SKILLS_DIR/tdd"
ln -s "$SOURCE_DIR/skills/engineering/tdd" "$PROJECT_SKILLS_DIR/tdd"
ln -s "$TEST_ROOT/missing-skill" "$USER_SKILLS_DIR/teach"
if "$INSTALLER" personal \
  --source-dir "$SOURCE_DIR" \
  --user-skills-dir "$USER_SKILLS_DIR" \
  --project "$PROJECT_DIR" >/dev/null 2>&1; then
  fail "expected a broken user-scope skill link to fail"
fi

printf 'PASS: install-matt-pocock-skills profiles, idempotency, and collision safety\n'
