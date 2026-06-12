#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
screenshot_command="${script_dir}/screenshot-to-clipboard.sh area"
custom_path="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/print-screen-clipboard/"
custom_schema="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:${custom_path}"
media_schema="org.gnome.settings-daemon.plugins.media-keys"
shell_schema="org.gnome.shell.keybindings"

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$1" >&2
    exit 127
  fi
}

custom_keybindings() {
  gsettings get "${media_schema}" custom-keybindings
}

append_custom_keybinding() {
  local current
  local next

  current="$(custom_keybindings)"
  case "${current}" in
    *"${custom_path}"*)
      return
      ;;
    "@as []"|"[]")
      next="['${custom_path}']"
      ;;
    *)
      next="${current%]}, '${custom_path}']"
      ;;
  esac

  gsettings set "${media_schema}" custom-keybindings "${next}"
}

remove_custom_keybinding() {
  local current
  local next
  local quoted_path

  current="$(custom_keybindings)"
  quoted_path="'${custom_path}'"
  next="${current}"
  next="${next//, ${quoted_path}/}"
  next="${next//${quoted_path}, /}"
  next="${next//${quoted_path}/}"

  if [[ "${next}" == "[]" ]]; then
    next="@as []"
  fi

  gsettings set "${media_schema}" custom-keybindings "${next}"
}

install_binding() {
  need_cmd gsettings
  need_cmd import
  need_cmd xclip

  gsettings set "${shell_schema}" show-screenshot-ui "@as []"
  append_custom_keybinding
  gsettings set "${custom_schema}" name "Print Screen to Clipboard"
  gsettings set "${custom_schema}" command "${screenshot_command}"
  gsettings set "${custom_schema}" binding "Print"
}

uninstall_binding() {
  need_cmd gsettings

  gsettings set "${custom_schema}" binding ""
  gsettings set "${custom_schema}" command ""
  gsettings set "${custom_schema}" name ""
  remove_custom_keybinding
  gsettings set "${shell_schema}" show-screenshot-ui "['Print']"
}

status() {
  need_cmd gsettings

  printf 'GNOME screenshot UI binding: '
  gsettings get "${shell_schema}" show-screenshot-ui
  printf 'Custom keybindings: '
  custom_keybindings

  if custom_keybindings | grep -F "${custom_path}" >/dev/null 2>&1; then
    printf 'Custom binding name: '
    gsettings get "${custom_schema}" name
    printf 'Custom binding command: '
    gsettings get "${custom_schema}" command
    printf 'Custom binding key: '
    gsettings get "${custom_schema}" binding
  fi
}

test_clipboard() {
  "${script_dir}/screenshot-to-clipboard.sh" screen
  xclip -selection clipboard -target TARGETS -o
}

case "${1:-install}" in
  install)
    install_binding
    status
    ;;
  uninstall)
    uninstall_binding
    status
    ;;
  status)
    status
    ;;
  test)
    test_clipboard
    ;;
  *)
    printf 'Usage: %s [install|uninstall|status|test]\n' "$0" >&2
    exit 64
    ;;
esac
