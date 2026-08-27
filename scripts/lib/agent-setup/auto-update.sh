#!/usr/bin/env bash

AUTO_UPDATE_SERVICE="agent-setup-skills-update.service"
AUTO_UPDATE_TIMER="agent-setup-skills-update.timer"
LEGACY_AUTO_UPDATE_SERVICE="codex-matt-pocock-skills-update.service"
LEGACY_AUTO_UPDATE_TIMER="codex-matt-pocock-skills-update.timer"

unit_quote() {
  local value="$1"
  value="${value//%/%%}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "$value"
}

require_linux_systemd_user() {
  case "$PLATFORM" in linux|wsl) ;; *) fail "scheduled updates are supported only on Linux or systemd-enabled WSL" ;; esac
  require_command systemctl
  require_command systemd-analyze
}

new_service_path() {
  printf '%s\n' "${SYSTEMD_USER_DIR}/${AUTO_UPDATE_SERVICE}"
}

new_timer_path() {
  printf '%s\n' "${SYSTEMD_USER_DIR}/${AUTO_UPDATE_TIMER}"
}

write_auto_update_units() {
  local service_path
  local timer_path
  local update_log

  service_path="$(new_service_path)"
  timer_path="$(new_timer_path)"
  update_log="${AUTO_UPDATE_STATE_DIR}/update.log"

  systemd-analyze calendar "$AUTO_UPDATE_CALENDAR" >/dev/null
  mkdir -p "$SYSTEMD_USER_DIR" "$AUTO_UPDATE_STATE_DIR"

  {
    printf '%s\n' \
      '[Unit]' \
      'Description=Update managed Agent skills' \
      'Wants=network-online.target' \
      'After=network-online.target' \
      '' \
      '[Service]' \
      'Type=oneshot'
    printf 'ExecStart=%s skills --profile %s --scope user --agent %s --ref %s --source-root %s\n' \
      "$(unit_quote "$INSTALLER_PATH")" \
      "$(unit_quote "$PROFILE")" \
      "$(unit_quote "$AGENT_TARGET")" \
      "$(unit_quote "$UPSTREAM_REF")" \
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
      'Description=Weekly update for managed Agent skills' \
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

disable_legacy_auto_update() {
  local legacy_service_path="${SYSTEMD_USER_DIR}/${LEGACY_AUTO_UPDATE_SERVICE}"
  local legacy_timer_path="${SYSTEMD_USER_DIR}/${LEGACY_AUTO_UPDATE_TIMER}"

  systemctl --user disable --now "$LEGACY_AUTO_UPDATE_TIMER" >/dev/null 2>&1 || true
  systemctl --user stop "$LEGACY_AUTO_UPDATE_SERVICE" >/dev/null 2>&1 || true
  [[ ! -e "$legacy_service_path" ]] || unlink "$legacy_service_path"
  [[ ! -e "$legacy_timer_path" ]] || unlink "$legacy_timer_path"
}

enable_auto_update() {
  [[ -n "$PROFILE" ]] || fail "auto-update enable requires --profile personal or --profile work"
  [[ "$SCOPE" == "user" ]] || fail "scheduled updates support only user scope"
  [[ -z "$EXTERNAL_SOURCE_DIR" ]] || fail "scheduled updates do not support --source-dir"
  [[ "${AGENT_SETUP_EPHEMERAL:-false}" != "true" ]] ||
    fail "cannot enable a timer from an ephemeral downloaded installer; use a local repository checkout"
  [[ -f "$INSTALLER_PATH" ]] || fail "installer must be a persistent local file: ${INSTALLER_PATH}"

  require_linux_systemd_user
  write_auto_update_units
  disable_legacy_auto_update
  systemctl --user daemon-reload

  log "Running an immediate skill update before enabling the timer."
  systemctl --user start "$AUTO_UPDATE_SERVICE"
  systemctl --user enable --now "$AUTO_UPDATE_TIMER"
  log "Automatic skill updates enabled: profile=${PROFILE}, agent=${AGENT_TARGET}, calendar=${AUTO_UPDATE_CALENDAR}"
  log "Log: ${AUTO_UPDATE_STATE_DIR}/update.log"
  systemctl --user list-timers --all "$AUTO_UPDATE_TIMER" --no-pager
}

disable_auto_update() {
  local service_path
  local timer_path

  require_linux_systemd_user
  service_path="$(new_service_path)"
  timer_path="$(new_timer_path)"

  systemctl --user disable --now "$AUTO_UPDATE_TIMER" >/dev/null 2>&1 || true
  systemctl --user stop "$AUTO_UPDATE_SERVICE" >/dev/null 2>&1 || true
  disable_legacy_auto_update
  [[ ! -e "$service_path" ]] || unlink "$service_path"
  [[ ! -e "$timer_path" ]] || unlink "$timer_path"
  systemctl --user daemon-reload
  systemctl --user reset-failed "$AUTO_UPDATE_SERVICE" "$AUTO_UPDATE_TIMER" >/dev/null 2>&1 || true
  log "Automatic skill updates disabled."
}

show_auto_update_status() {
  local timer_name="$AUTO_UPDATE_TIMER"

  require_linux_systemd_user
  if [[ ! -e "$(new_timer_path)" && -e "${SYSTEMD_USER_DIR}/${LEGACY_AUTO_UPDATE_TIMER}" ]]; then
    timer_name="$LEGACY_AUTO_UPDATE_TIMER"
  fi
  systemctl --user status "$timer_name" --no-pager
  systemctl --user list-timers --all "$timer_name" --no-pager
}

warn_if_timer_configuration_differs() {
  local service_path

  service_path="$(new_service_path)"
  [[ -f "$service_path" ]] || return 0
  if ! grep -Fq -- "--profile \"${PROFILE}\"" "$service_path" ||
    ! grep -Fq -- "--agent \"${AGENT_TARGET}\"" "$service_path"; then
    warn "active updater configuration differs from this manual install; re-enable auto-update to prevent the timer from restoring another profile or Agent target"
  fi
}

manage_auto_update() {
  case "$AUTO_UPDATE_ACTION" in
    enable) enable_auto_update ;;
    disable) disable_auto_update ;;
    status) show_auto_update_status ;;
    *) fail "auto-update action must be one of: enable, disable, status" ;;
  esac
}
