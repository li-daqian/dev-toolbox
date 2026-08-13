#!/bin/sh
set -eu

SNAP_RETAIN="${SNAP_RETAIN:-2}"
JOURNAL_RETENTION="${JOURNAL_RETENTION:-7d}"

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

run() {
  echo
  echo "==> $*"
  "$@"
}

run_sudo() {
  run sudo "$@"
}

show_disk_usage() {
  echo
  echo "Disk usage:"
  df -h /
}

cleanup_apt() {
  if ! command_exists apt-get; then
    echo "apt-get not found, skipping apt cleanup."
    return
  fi

  run_sudo apt-get -y autoclean
  run_sudo apt-get clean
  run_sudo apt-get -y --purge autoremove

  if [ -d /var/lib/apt/lists ]; then
    # Apt will re-download package indexes on the next update.
    run_sudo rm -rf /var/lib/apt/lists/*
  fi
}

cleanup_docker() {
  if ! command_exists docker; then
    echo "docker not found, skipping docker cleanup."
    return
  fi

  if ! sudo docker info >/dev/null 2>&1; then
    echo "docker daemon unavailable, skipping docker cleanup."
    return
  fi

  # Volumes may contain durable application data, so never prune them here.
  run_sudo docker system prune -a -f
}

cleanup_snap() {
  if ! command_exists snap; then
    echo "snap not found, skipping snap cleanup."
    return
  fi

  run_sudo snap set system refresh.retain="$SNAP_RETAIN"

  # Remove already-downloaded disabled revisions, not just future retention.
  snap list --all 2>/dev/null | awk '/disabled/{print $1, $3}' | while read -r snap_name revision; do
    [ -n "$snap_name" ] || continue
    run_sudo snap remove "$snap_name" --revision="$revision"
  done
}

cleanup_journal() {
  if ! command_exists journalctl; then
    echo "journalctl not found, skipping journal cleanup."
    return
  fi

  run_sudo journalctl --vacuum-time="$JOURNAL_RETENTION"
}

cleanup_crash_reports() {
  if [ ! -d /var/crash ]; then
    echo "/var/crash not found, skipping crash report cleanup."
    return
  fi

  run_sudo find /var/crash -mindepth 1 -delete
}

main() {
  echo "Ubuntu disk cleanup started."
  echo "SNAP_RETAIN=$SNAP_RETAIN"
  echo "JOURNAL_RETENTION=$JOURNAL_RETENTION"

  show_disk_usage
  cleanup_apt
  cleanup_docker
  cleanup_snap
  cleanup_journal
  cleanup_crash_reports
  show_disk_usage

  echo
  echo "Cleanup completed."
}

main "$@"
