#!/usr/bin/env bash
set -euo pipefail

UPSTREAM_REPO="https://github.com/mattpocock/skills.git"
UPSTREAM_REF="main"
PROFILE=""
AUTO_UPDATE_ACTION=""
AUTO_UPDATE_CALENDAR="Mon *-*-* 09:00:00"
PROJECT_DIR="${PWD}"
USER_SKILLS_DIR="${HOME}/.agents/skills"
MANAGED_SOURCE_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/codex-skill-sources/mattpocock-skills"
SYSTEMD_USER_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/systemd/user"
AUTO_UPDATE_STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/codex-skill-updater"
SOURCE_DIR=""

AUTO_UPDATE_SERVICE="codex-matt-pocock-skills-update.service"
AUTO_UPDATE_TIMER="codex-matt-pocock-skills-update.timer"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename "${BASH_SOURCE[0]}")"

WORK_SKILL_PATHS=(
  "skills/productivity/grilling"
  "skills/productivity/grill-me"
  "skills/engineering/diagnosing-bugs"
  "skills/engineering/domain-modeling"
  "skills/engineering/grill-with-docs"
)

usage() {
  cat <<'EOF'
Usage:
  ./scripts/install-matt-pocock-skills.sh work [options]
  ./scripts/install-matt-pocock-skills.sh personal [options]
  ./scripts/install-matt-pocock-skills.sh auto-update enable [options]
  ./scripts/install-matt-pocock-skills.sh auto-update disable [options]
  ./scripts/install-matt-pocock-skills.sh auto-update status [options]

Profiles:
  work       Install five curated skills into the Codex user scope.
  personal   Make the complete stable upstream set available in one Git project.
             Existing user-scope skills are reused instead of duplicated.
  auto-update
             Manage a systemd user timer that refreshes the work profile.

Options:
  --project <path>          Personal project path. Default: current directory
  --ref <git-ref>           Upstream Git ref. Default: main
  --user-skills-dir <path>  Codex user skill directory. Default: ~/.agents/skills
  --source-root <path>      Managed upstream clone. Default:
                            ~/.local/share/codex-skill-sources/mattpocock-skills
  --source-dir <path>       Use an existing checkout without fetching it
  --calendar <expression>   systemd calendar for automatic updates. Default:
                            Mon *-*-* 09:00:00
  --systemd-user-dir <path> systemd user unit directory. Default:
                            ~/.config/systemd/user
  --state-dir <path>        Automatic-update log directory. Default:
                            ~/.local/state/codex-skill-updater
  --help                    Show this help

Examples:
  ./scripts/install-matt-pocock-skills.sh work
  ./scripts/install-matt-pocock-skills.sh personal --project ~/Code/my-project
  ./scripts/install-matt-pocock-skills.sh work --ref v1.0.0
  ./scripts/install-matt-pocock-skills.sh auto-update enable
  ./scripts/install-matt-pocock-skills.sh auto-update status

Re-run the same command to fetch the selected ref and update every managed skill.
The upstream skill directories are never edited; Codex follows symlinks to them.
EOF
}

log() {
  printf '%s\n' "$*"
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 is required."
}

unit_quote() {
  local value="$1"

  value="${value//%/%%}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "$value"
}

write_auto_update_units() {
  local service_path="${SYSTEMD_USER_DIR}/${AUTO_UPDATE_SERVICE}"
  local timer_path="${SYSTEMD_USER_DIR}/${AUTO_UPDATE_TIMER}"
  local update_log="${AUTO_UPDATE_STATE_DIR}/update.log"

  require_command systemd-analyze
  systemd-analyze calendar "$AUTO_UPDATE_CALENDAR" >/dev/null

  mkdir -p "$SYSTEMD_USER_DIR" "$AUTO_UPDATE_STATE_DIR"

  {
    printf '%s\n' \
      '[Unit]' \
      'Description=Update Matt Pocock skills for Codex' \
      'Wants=network-online.target' \
      'After=network-online.target' \
      '' \
      '[Service]' \
      'Type=oneshot'
    printf 'ExecStart=%s work --ref %s --user-skills-dir %s --source-root %s\n' \
      "$(unit_quote "$SCRIPT_PATH")" \
      "$(unit_quote "$UPSTREAM_REF")" \
      "$(unit_quote "$USER_SKILLS_DIR")" \
      "$(unit_quote "$MANAGED_SOURCE_DIR")"
    printf '%s\n' \
      'Environment=GIT_TERMINAL_PROMPT=0' \
      'TimeoutStartSec=15min' \
      'UMask=0077'
    printf 'StandardOutput=append:%s\n' "$update_log"
    printf 'StandardError=append:%s\n' "$update_log"
  } > "$service_path"

  {
    printf '%s\n' \
      '[Unit]' \
      'Description=Weekly update for Matt Pocock Codex skills' \
      '' \
      '[Timer]'
    printf 'OnCalendar=%s\n' "$AUTO_UPDATE_CALENDAR"
    printf '%s\n' \
      'Persistent=true' \
      "Unit=${AUTO_UPDATE_SERVICE}" \
      '' \
      '[Install]' \
      'WantedBy=timers.target'
  } > "$timer_path"

  systemd-analyze verify "$service_path" "$timer_path" >/dev/null
}

enable_auto_update() {
  require_command systemctl
  write_auto_update_units
  systemctl --user daemon-reload

  log 'Running an immediate update before enabling the timer.'
  systemctl --user start "$AUTO_UPDATE_SERVICE"
  systemctl --user enable --now "$AUTO_UPDATE_TIMER"

  log "Automatic updates enabled: ${AUTO_UPDATE_CALENDAR}"
  log "Timer: ${AUTO_UPDATE_TIMER}"
  log "Log: ${AUTO_UPDATE_STATE_DIR}/update.log"
  systemctl --user list-timers --all "$AUTO_UPDATE_TIMER" --no-pager
}

disable_auto_update() {
  local service_path="${SYSTEMD_USER_DIR}/${AUTO_UPDATE_SERVICE}"
  local timer_path="${SYSTEMD_USER_DIR}/${AUTO_UPDATE_TIMER}"

  require_command systemctl
  systemctl --user disable --now "$AUTO_UPDATE_TIMER" >/dev/null 2>&1 || true
  systemctl --user stop "$AUTO_UPDATE_SERVICE" >/dev/null 2>&1 || true

  [[ ! -e "$service_path" ]] || unlink "$service_path"
  [[ ! -e "$timer_path" ]] || unlink "$timer_path"

  systemctl --user daemon-reload
  systemctl --user reset-failed "$AUTO_UPDATE_SERVICE" "$AUTO_UPDATE_TIMER" \
    >/dev/null 2>&1 || true
  log 'Automatic updates disabled.'
}

show_auto_update_status() {
  require_command systemctl
  systemctl --user status "$AUTO_UPDATE_TIMER" --no-pager
  systemctl --user list-timers --all "$AUTO_UPDATE_TIMER" --no-pager
}

manage_auto_update() {
  case "$AUTO_UPDATE_ACTION" in
    enable)
      enable_auto_update
      ;;
    disable)
      disable_auto_update
      ;;
    status)
      show_auto_update_status
      ;;
    *)
      fail 'auto-update action must be one of: enable, disable, status'
      ;;
  esac
}

canonical_dir() {
  (cd "$1" >/dev/null 2>&1 && pwd -P)
}

prepare_source() {
  if [[ -n "$SOURCE_DIR" ]]; then
    [[ -d "$SOURCE_DIR" ]] || fail "source directory does not exist: ${SOURCE_DIR}"
    SOURCE_DIR="$(canonical_dir "$SOURCE_DIR")"
    log "Using existing upstream checkout: ${SOURCE_DIR}"
    return
  fi

  require_command git
  SOURCE_DIR="$MANAGED_SOURCE_DIR"

  if [[ -e "$SOURCE_DIR" && ! -d "$SOURCE_DIR/.git" ]]; then
    fail "managed source exists but is not a Git checkout: ${SOURCE_DIR}"
  fi

  if [[ ! -d "$SOURCE_DIR/.git" ]]; then
    mkdir -p "$(dirname "$SOURCE_DIR")"
    log "Cloning ${UPSTREAM_REPO} into ${SOURCE_DIR}"
    git clone --depth 1 "$UPSTREAM_REPO" "$SOURCE_DIR"
  fi

  if [[ -n "$(git -C "$SOURCE_DIR" status --porcelain --untracked-files=all)" ]]; then
    fail "managed upstream checkout has local changes; refusing to overwrite: ${SOURCE_DIR}"
  fi

  log "Updating upstream source to ${UPSTREAM_REF}"
  git -C "$SOURCE_DIR" fetch --depth 1 origin "$UPSTREAM_REF"
  git -C "$SOURCE_DIR" checkout --detach FETCH_HEAD >/dev/null
  SOURCE_DIR="$(canonical_dir "$SOURCE_DIR")"
}

validate_skill_dir() {
  local skill_dir="$1"
  [[ -f "$skill_dir/SKILL.md" ]] || fail "missing SKILL.md in upstream skill: ${skill_dir}"
}

collect_work_skills() {
  local relative_path

  SELECTED_SKILL_DIRS=()
  for relative_path in "${WORK_SKILL_PATHS[@]}"; do
    validate_skill_dir "$SOURCE_DIR/$relative_path"
    SELECTED_SKILL_DIRS+=("$SOURCE_DIR/$relative_path")
  done
}

collect_personal_skills() {
  local bucket
  local skill_dir

  SELECTED_SKILL_DIRS=()
  shopt -s nullglob
  for bucket in engineering productivity misc; do
    for skill_dir in "$SOURCE_DIR/skills/$bucket"/*; do
      [[ -d "$skill_dir" && -f "$skill_dir/SKILL.md" ]] || continue
      SELECTED_SKILL_DIRS+=("$skill_dir")
    done
  done
  shopt -u nullglob

  [[ ${#SELECTED_SKILL_DIRS[@]} -gt 0 ]] || fail "no stable skills found in ${SOURCE_DIR}"
}

resolve_personal_target() {
  require_command git
  [[ -d "$PROJECT_DIR" ]] || fail "project directory does not exist: ${PROJECT_DIR}"
  PROJECT_ROOT="$(git -C "$PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null)" ||
    fail "personal profile requires a Git project: ${PROJECT_DIR}"
  PROJECT_SKILLS_DIR="${PROJECT_ROOT}/.agents/skills"
}

resolved_link_target() {
  local link_path="$1"
  readlink -f "$link_path" 2>/dev/null || true
}

preflight_destination() {
  local destination="$1"
  local source_skill="$2"
  local existing_target
  local expected_target

  if [[ -L "$destination" ]]; then
    existing_target="$(resolved_link_target "$destination")"
    expected_target="$(canonical_dir "$source_skill")"
    [[ "$existing_target" == "$expected_target" ]] ||
      fail "skill destination is linked to another source: ${destination} -> ${existing_target}"
    return
  fi

  [[ ! -e "$destination" ]] ||
    fail "skill destination already exists and is not managed by this script: ${destination}"
}

plan_installation() {
  local skill_dir
  local skill_name
  local destination

  INSTALL_SOURCES=()
  INSTALL_DESTINATIONS=()
  REUSED_USER_SKILLS=()

  for skill_dir in "${SELECTED_SKILL_DIRS[@]}"; do
    skill_name="$(basename "$skill_dir")"

    if [[ "$PROFILE" == "personal" ]]; then
      if [[ -L "$USER_SKILLS_DIR/$skill_name" && ! -e "$USER_SKILLS_DIR/$skill_name" ]]; then
        fail "user-scope skill is a broken symlink: ${USER_SKILLS_DIR}/${skill_name}"
      fi
      if [[ -e "$USER_SKILLS_DIR/$skill_name" ]]; then
        REUSED_USER_SKILLS+=("$skill_name")
        continue
      fi
    fi

    if [[ "$PROFILE" == "work" ]]; then
      destination="$USER_SKILLS_DIR/$skill_name"
    else
      destination="$PROJECT_SKILLS_DIR/$skill_name"
    fi

    preflight_destination "$destination" "$skill_dir"
    INSTALL_SOURCES+=("$skill_dir")
    INSTALL_DESTINATIONS+=("$destination")
  done
}

apply_installation() {
  local index
  local destination
  local source_skill

  mkdir -p "$USER_SKILLS_DIR"
  if [[ "$PROFILE" == "personal" ]]; then
    mkdir -p "$PROJECT_SKILLS_DIR"
  fi

  for index in "${!INSTALL_SOURCES[@]}"; do
    source_skill="${INSTALL_SOURCES[$index]}"
    destination="${INSTALL_DESTINATIONS[$index]}"
    if [[ -L "$destination" ]]; then
      log "Already installed: $(basename "$destination")"
      continue
    fi

    ln -s "$source_skill" "$destination"
    log "Installed: $(basename "$destination") -> ${source_skill}"
  done
}

print_summary() {
  local source_revision="external checkout"

  if [[ -d "$SOURCE_DIR/.git" ]]; then
    source_revision="$(git -C "$SOURCE_DIR" rev-parse --short HEAD)"
  fi

  log "Profile '${PROFILE}' is ready from upstream revision ${source_revision}."
  if [[ "$PROFILE" == "work" ]]; then
    log "User skills directory: ${USER_SKILLS_DIR}"
  else
    log "Project skills directory: ${PROJECT_SKILLS_DIR}"
    if [[ ${#REUSED_USER_SKILLS[@]} -gt 0 ]]; then
      log "Reused ${#REUSED_USER_SKILLS[@]} user-scope skill(s) to avoid duplicate names."
    fi
  fi
  log "Restart Codex if the installed skills do not appear immediately."
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

[[ $# -gt 0 ]] || {
  usage
  exit 1
}

PROFILE="$1"
shift

if [[ "$PROFILE" == "auto-update" ]]; then
  [[ $# -gt 0 ]] || fail 'auto-update requires an action: enable, disable, or status'
  AUTO_UPDATE_ACTION="$1"
  shift
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
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
    --user-skills-dir)
      [[ $# -ge 2 ]] || fail "--user-skills-dir requires a value"
      USER_SKILLS_DIR="$2"
      shift 2
      ;;
    --source-root)
      [[ $# -ge 2 ]] || fail "--source-root requires a value"
      MANAGED_SOURCE_DIR="$2"
      shift 2
      ;;
    --source-dir)
      [[ $# -ge 2 ]] || fail "--source-dir requires a value"
      SOURCE_DIR="$2"
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
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

case "$PROFILE" in
  work|personal|auto-update)
    ;;
  *)
    fail "profile must be one of: work, personal, auto-update"
    ;;
esac

if [[ "$PROFILE" == "auto-update" ]]; then
  manage_auto_update
  exit 0
fi

prepare_source

case "$PROFILE" in
  work)
    collect_work_skills
    ;;
  personal)
    resolve_personal_target
    collect_personal_skills
    ;;
esac

plan_installation
apply_installation
print_summary
