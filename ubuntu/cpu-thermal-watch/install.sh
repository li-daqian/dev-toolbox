#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="cpu-thermal-watch.service"
SCRIPT_PATH="/usr/local/sbin/cpu-thermal-watch.sh"
ENV_PATH="/etc/default/cpu-thermal-watch"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}"
MODE_PATH="/run/cpu-thermal-watch.mode"

HIGH_TEMP_C="${HIGH_TEMP_C:-78}"
LOW_TEMP_C="${LOW_TEMP_C:-68}"
POLL_INTERVAL_S="${POLL_INTERVAL_S:-1}"
FAST_ON_AC_ONLY="${FAST_ON_AC_ONLY:-1}"
ENABLE_THERMALD="${ENABLE_THERMALD:-1}"
MANAGE_THROTTLED="${MANAGE_THROTTLED:-1}"

usage() {
  cat <<'EOF'
Usage:
  ./ubuntu/cpu-thermal-watch/install.sh [install|status|uninstall] [options]

Commands:
  install      Install or update the watchdog service. Default command.
  status       Print service status and current mode.
  uninstall    Remove the watchdog service and restore default thermal services.

Options:
  --high-temp <celsius>     Safe-mode entry threshold. Default: 78
  --low-temp <celsius>      Fast-mode entry threshold. Default: 68
  --poll-interval <sec>     Temperature polling interval. Default: 1
  --allow-battery-fast      Allow fast mode on battery. Default: disabled
  --disable-thermald        Do not restart thermald in safe mode
  --disable-throttled-stop  Do not manage throttled
  --help                    Show this help

Examples:
  ./ubuntu/cpu-thermal-watch/install.sh
  HIGH_TEMP_C=75 LOW_TEMP_C=65 ./ubuntu/cpu-thermal-watch/install.sh install
  ./ubuntu/cpu-thermal-watch/install.sh status
  ./ubuntu/cpu-thermal-watch/install.sh uninstall
EOF
}

log() {
  printf '%s\n' "$*"
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

run_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

render_watch_script() {
  cat <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

MODE_FILE=/run/cpu-thermal-watch.mode

POLL_INTERVAL_S="${POLL_INTERVAL_S:-1}"
HIGH_TEMP_C="${HIGH_TEMP_C:-78}"
LOW_TEMP_C="${LOW_TEMP_C:-68}"
FAST_ON_AC_ONLY="${FAST_ON_AC_ONLY:-1}"
ENABLE_THERMALD="${ENABLE_THERMALD:-1}"
MANAGE_THROTTLED="${MANAGE_THROTTLED:-1}"

THERMAL_MODULES=(
  processor_thermal_device_pci_legacy
  processor_thermal_device
  processor_thermal_power_floor
  processor_thermal_wt_req
  processor_thermal_wt_hint
  processor_thermal_rfim
  processor_thermal_rapl
  intel_soc_dts_iosf
  int340x_thermal_zone
  processor_thermal_mbox
)

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

mode() {
  if [[ -f "$MODE_FILE" ]]; then
    cat "$MODE_FILE"
  else
    printf 'unknown\n'
  fi
}

set_mode() {
  printf '%s\n' "$1" >"$MODE_FILE"
}

pkg_temp_c() {
  local zone type temp
  for zone in /sys/class/thermal/thermal_zone*; do
    [[ -f "$zone/type" && -f "$zone/temp" ]] || continue
    type="$(<"$zone/type")"
    if [[ "$type" == "x86_pkg_temp" ]]; then
      temp="$(<"$zone/temp")"
      printf '%s\n' "$((temp / 1000))"
      return 0
    fi
  done
  return 1
}

on_ac() {
  [[ -f /sys/class/power_supply/AC/online ]] && [[ "$(< /sys/class/power_supply/AC/online)" == "1" ]]
}

stop_limiters() {
  if [[ "$MANAGE_THROTTLED" == "1" ]]; then
    systemctl stop throttled.service 2>/dev/null || true
  fi
  if [[ "$ENABLE_THERMALD" == "1" ]]; then
    systemctl stop thermald.service 2>/dev/null || true
  fi
}

start_safe_services() {
  if [[ "$ENABLE_THERMALD" == "1" ]]; then
    systemctl start thermald.service 2>/dev/null || true
  fi
  if [[ "$MANAGE_THROTTLED" == "1" ]]; then
    systemctl stop throttled.service 2>/dev/null || true
  fi
}

unload_thermal_modules() {
  modprobe -r "${THERMAL_MODULES[@]}" 2>/dev/null || true
}

load_thermal_modules() {
  modprobe intel_soc_dts_iosf 2>/dev/null || true
  modprobe int340x_thermal_zone 2>/dev/null || true
  modprobe processor_thermal_mbox 2>/dev/null || true
  modprobe processor_thermal_power_floor 2>/dev/null || true
  modprobe processor_thermal_wt_req 2>/dev/null || true
  modprobe processor_thermal_wt_hint 2>/dev/null || true
  modprobe processor_thermal_rfim 2>/dev/null || true
  modprobe processor_thermal_rapl 2>/dev/null || true
  modprobe processor_thermal_device 2>/dev/null || true
  modprobe processor_thermal_device_pci_legacy 2>/dev/null || true
}

enter_fast_mode() {
  stop_limiters
  unload_thermal_modules
  if [[ "$(mode)" != "fast" ]]; then
    set_mode fast
    log "entered fast mode"
  fi
}

enter_safe_mode() {
  load_thermal_modules
  start_safe_services
  if [[ "$(mode)" != "safe" ]]; then
    set_mode safe
    log "entered safe mode"
  fi
}

restore_safe_mode() {
  enter_safe_mode
}

main() {
  local temp_c current_mode target ac_state

  if (( HIGH_TEMP_C <= LOW_TEMP_C )); then
    log "invalid threshold config: HIGH_TEMP_C must be greater than LOW_TEMP_C"
    exit 1
  fi

  trap restore_safe_mode EXIT TERM INT

  while true; do
    if ! temp_c="$(pkg_temp_c)"; then
      log "x86_pkg_temp not found; forcing safe mode"
      enter_safe_mode
      sleep "$POLL_INTERVAL_S"
      continue
    fi

    current_mode="$(mode)"
    ac_state=0
    if on_ac; then
      ac_state=1
    fi

    if [[ "$FAST_ON_AC_ONLY" == "1" && "$ac_state" != "1" ]]; then
      target=safe
    elif (( temp_c >= HIGH_TEMP_C )); then
      target=safe
    elif (( temp_c <= LOW_TEMP_C )); then
      target=fast
    else
      target="$current_mode"
      if [[ "$target" == "unknown" ]]; then
        target=safe
      fi
    fi

    if [[ "$target" != "$current_mode" ]]; then
      log "temp=${temp_c}C ac=${ac_state} target=${target}"
      if [[ "$target" == "fast" ]]; then
        enter_fast_mode
      else
        enter_safe_mode
      fi
    fi

    sleep "$POLL_INTERVAL_S"
  done
}

main "$@"
EOF
}

render_env_file() {
  cat <<EOF
# Hot threshold that forces safe mode.
HIGH_TEMP_C=${HIGH_TEMP_C}

# Cool threshold that allows returning to fast mode.
LOW_TEMP_C=${LOW_TEMP_C}

# Poll interval for temperature checks.
POLL_INTERVAL_S=${POLL_INTERVAL_S}

# Only allow fast mode while on AC power.
FAST_ON_AC_ONLY=${FAST_ON_AC_ONLY}

# Keep thermald active in safe mode.
ENABLE_THERMALD=${ENABLE_THERMALD}

# Always keep throttled stopped while this watchdog is running.
MANAGE_THROTTLED=${MANAGE_THROTTLED}
EOF
}

render_service_file() {
  cat <<'EOF'
[Unit]
Description=CPU thermal mode watchdog
After=multi-user.target
ConditionPathExists=/sys/class/thermal

[Service]
Type=simple
EnvironmentFile=-/etc/default/cpu-thermal-watch
ExecStart=/usr/local/sbin/cpu-thermal-watch.sh
Restart=always
RestartSec=2
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
}

install_service() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN

  render_watch_script >"${tmpdir}/cpu-thermal-watch.sh"
  render_env_file >"${tmpdir}/cpu-thermal-watch.env"
  render_service_file >"${tmpdir}/cpu-thermal-watch.service"

  run_root install -m 0755 "${tmpdir}/cpu-thermal-watch.sh" "${SCRIPT_PATH}"
  run_root install -m 0644 "${tmpdir}/cpu-thermal-watch.env" "${ENV_PATH}"
  run_root install -m 0644 "${tmpdir}/cpu-thermal-watch.service" "${SERVICE_PATH}"

  run_root systemctl disable --now throttled.service || true
  run_root systemctl daemon-reload
  run_root systemctl enable --now "${SERVICE_NAME}"

  log "Installed ${SERVICE_NAME}"
}

print_status() {
  log "Kernel: $(uname -r)"
  if [[ -f "${MODE_PATH}" ]]; then
    log "Mode: $(<"${MODE_PATH}")"
  else
    log "Mode: unknown"
  fi
  run_root systemctl status "${SERVICE_NAME}" --no-pager || true
}

uninstall_service() {
  run_root systemctl disable --now "${SERVICE_NAME}" || true
  run_root rm -f "${SERVICE_PATH}" "${SCRIPT_PATH}" "${ENV_PATH}"
  run_root systemctl daemon-reload
  run_root systemctl reset-failed "${SERVICE_NAME}" || true
  run_root systemctl start thermald.service || true
  log "Removed ${SERVICE_NAME}"
  log "Note: throttled was not re-enabled automatically."
}

COMMAND="install"
while [[ $# -gt 0 ]]; do
  case "$1" in
    install|status|uninstall)
      COMMAND="$1"
      shift
      ;;
    --high-temp)
      [[ $# -ge 2 ]] || fail "--high-temp requires a value"
      HIGH_TEMP_C="$2"
      shift 2
      ;;
    --low-temp)
      [[ $# -ge 2 ]] || fail "--low-temp requires a value"
      LOW_TEMP_C="$2"
      shift 2
      ;;
    --poll-interval)
      [[ $# -ge 2 ]] || fail "--poll-interval requires a value"
      POLL_INTERVAL_S="$2"
      shift 2
      ;;
    --allow-battery-fast)
      FAST_ON_AC_ONLY=0
      shift
      ;;
    --disable-thermald)
      ENABLE_THERMALD=0
      shift
      ;;
    --disable-throttled-stop)
      MANAGE_THROTTLED=0
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

case "${COMMAND}" in
  install)
    install_service
    print_status
    ;;
  status)
    print_status
    ;;
  uninstall)
    uninstall_service
    ;;
esac
