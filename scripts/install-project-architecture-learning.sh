#!/usr/bin/env bash
set -euo pipefail

SCRIPT_SOURCE="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd -P)"
SKILL_SOURCE="${REPO_ROOT}/agent/skills/project-architecture-learning"
CODEX_SKILLS_DIR="${CODEX_HOME:-${HOME}/.codex}/skills"
SKILL_TARGET="${CODEX_SKILLS_DIR}/project-architecture-learning"

[[ -f "${SKILL_SOURCE}/SKILL.md" ]] || {
  printf 'Error: missing skill source: %s\n' "${SKILL_SOURCE}" >&2
  exit 1
}

mkdir -p "$CODEX_SKILLS_DIR"
if [[ -L "$SKILL_TARGET" || (-e "$SKILL_TARGET" && ! -d "$SKILL_TARGET") ]]; then
  printf 'Error: skill target is not a regular directory: %s\n' "$SKILL_TARGET" >&2
  exit 1
fi
if [[ -d "$SKILL_TARGET" ]]; then
  if cmp -s "${SKILL_SOURCE}/SKILL.md" "${SKILL_TARGET}/SKILL.md" &&
    cmp -s "${SKILL_SOURCE}/agents/openai.yaml" "${SKILL_TARGET}/agents/openai.yaml"; then
    printf 'Skill already current: %s\n' "$SKILL_TARGET"
    exit 0
  fi
fi

rm -rf "$SKILL_TARGET"
cp -R "$SKILL_SOURCE" "$SKILL_TARGET"
printf 'Installed skill: %s\n' "$SKILL_TARGET"
