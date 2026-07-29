#!/usr/bin/env bash
set -euo pipefail

RAW_BASE="${RAW_BASE:-https://raw.githubusercontent.com/li-daqian/dev-toolbox/main}"
SCRIPT_SOURCE="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_SOURCE")" && pwd)"

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

run_repo_script() {
  local script_path="$1"
  local runner="$2"
  local local_path="$SCRIPT_DIR/../$script_path"

  if ! command_exists "$runner"; then
    echo "$runner is required to run $script_path."
    exit 1
  fi

  if [[ -f "$local_path" ]]; then
    "$runner" "$local_path"
    return
  fi

  if ! command_exists curl; then
    echo "curl is required to download $script_path."
    exit 1
  fi

  curl -fsSL "$RAW_BASE/$script_path?$(date +%s)" | "$runner"
}

has_graphical_session() {
  [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" || -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]
}

set_gsetting() {
  local schema="$1"
  local key="$2"
  local value="$3"

  run gsettings set "$schema" "$key" "$value"
}

add_custom_shortcut() {
  local shortcut_id="$1"
  local name="$2"
  local shortcut_command="$3"
  local binding="$4"
  local shortcut_path="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/$shortcut_id/"
  local current
  local new_list

  current="$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings | sed 's/^@as //')"

  if echo "$current" | grep -q "$shortcut_path"; then
    echo "$name shortcut already configured."
  else
    if [[ "$current" == "[]" ]]; then
      new_list="['$shortcut_path']"
    else
      new_list="$(echo "$current" | sed "s|]$|, '$shortcut_path']|")"
    fi
    run gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$new_list"
  fi

  run gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"$shortcut_path" name "$name"
  run gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"$shortcut_path" command "$shortcut_command"
  run gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"$shortcut_path" binding "$binding"
}

configure_gnome_ui() {
  if ! command_exists gsettings; then
    echo "gsettings not found, skipping GNOME configuration."
    return
  fi

  if ! has_graphical_session; then
    echo "No graphical session detected, skipping GNOME configuration."
    return
  fi

  set_gsetting org.gnome.shell.extensions.dash-to-dock dock-position "BOTTOM"
  set_gsetting org.gnome.shell.extensions.dash-to-dock dock-fixed "true"
  set_gsetting org.gnome.shell.extensions.ding show-home "false"
  set_gsetting org.gnome.desktop.interface color-scheme "prefer-dark"
  set_gsetting org.gnome.desktop.interface text-scaling-factor "1.2"
  set_gsetting org.gnome.shell.extensions.dash-to-dock click-action "minimize"
  set_gsetting org.gnome.shell.extensions.dash-to-dock always-center-icons "true"
  set_gsetting org.gnome.desktop.interface clock-show-weekday "true"
  set_gsetting org.gnome.desktop.interface enable-animations "false"
  set_gsetting org.gnome.shell.extensions.dash-to-dock dash-max-icon-size "38"
  set_gsetting org.gnome.desktop.wm.keybindings switch-to-workspace-left "['<Control><Super>Left']"
  set_gsetting org.gnome.desktop.wm.keybindings switch-to-workspace-right "['<Control><Super>Right']"
}

configure_system_monitor_extension() {
  local extension_id="system-monitor@gnome-shell-extensions.gcampax.github.com"

  if ! command_exists gnome-extensions; then
    echo "gnome-extensions not found, skipping system monitor configuration."
    return
  fi

  if ! has_graphical_session; then
    echo "No graphical session detected, skipping GNOME extension configuration."
    return
  fi

  if ! gnome-extensions list | grep -qx "$extension_id"; then
    echo "GNOME system monitor extension is not installed. Skipping."
    return
  fi

  run gnome-extensions enable "$extension_id"
  set_gsetting org.gnome.shell.extensions.system-monitor show-cpu "true"
  set_gsetting org.gnome.shell.extensions.system-monitor show-memory "true"
  set_gsetting org.gnome.shell.extensions.system-monitor show-download "true"
  set_gsetting org.gnome.shell.extensions.system-monitor show-swap "false"
  set_gsetting org.gnome.shell.extensions.system-monitor show-upload "false"
}

configure_power() {
  if command_exists powerprofilesctl; then
    run_sudo powerprofilesctl set performance
  else
    echo "powerprofilesctl not found, skipping power profile configuration."
  fi

  if command_exists cpupower; then
    run_sudo cpupower frequency-set -g performance
  else
    echo "cpupower not found, skipping CPU governor configuration."
  fi
}

configure_swappiness() {
  run_sudo sysctl vm.swappiness=10

  if grep -q '^vm\.swappiness=' /etc/sysctl.conf; then
    run_sudo sed -i 's/^vm\.swappiness=.*/vm.swappiness=10/' /etc/sysctl.conf
  else
    printf '%s\n' 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf >/dev/null
  fi
}

install_xclip() {
  if command_exists xclip; then
    echo "xclip is already installed. Skipping xclip installation."
    return
  fi

  run_sudo apt-get install -y xclip
}

install_input_mono() {
  local tmp_dir

  if command_exists fc-list && fc-list | grep -q "Input Mono"; then
    echo "Input Mono is already installed. Skipping font installation."
    return
  fi

  echo "Input Mono font is not installed. Installing Input Mono font ..."
  tmp_dir="$(mktemp -d)"
  mkdir -p "$HOME/.local/share/fonts"
  curl -fsSL "https://input.djr.com/build/?fontSelection=whole&a=0&g=0&i=0&l=0&zero=0&asterisk=0&braces=0&preset=default&line-height=1.2&accept=I+do&email=" -o "$tmp_dir/Input-Font.zip"
  unzip -o "$tmp_dir/Input-Font.zip" -d "$tmp_dir/Input-Font" >/dev/null
  find "$tmp_dir/Input-Font" -type f -name 'InputMono-*.ttf' -exec cp {} "$HOME/.local/share/fonts/" \;
  rm -rf "$tmp_dir"
  fc-cache -f -v
}

install_rime() {
  run_repo_script "rime/install.sh" sh
}

install_albert() {
  run_repo_script "ubuntu/install-albert.sh" bash
}

install_copyq() {
  if ! command_exists copyq; then
    echo "CopyQ is not installed. Installing CopyQ ..."
    run_sudo apt-get install -y software-properties-common
    run_sudo add-apt-repository -y ppa:hluk/copyq
    run_sudo apt-get update
    run_sudo apt-get install -y copyq
  else
    echo "CopyQ is already installed. Skipping CopyQ installation."
  fi

  if ! command_exists copyq; then
    return
  fi

  if ! has_graphical_session || ! command_exists gsettings; then
    echo "No graphical session detected, skipping CopyQ shortcut and autostart configuration."
    return
  fi

  add_custom_shortcut "copyq-show" "Show CopyQ" "copyq toggle" "<Super>v"
  run copyq config autostart true
}

configure_gdm_for_copyq() {
  local gdm_config="/etc/gdm3/custom.conf"

  if [[ ! -f "$gdm_config" ]]; then
    echo "$gdm_config not found, skipping GDM configuration."
    return
  fi

  if grep -Eq '^[[:space:]]*#?[[:space:]]*WaylandEnable=' "$gdm_config"; then
    run_sudo sed -i 's/^[[:space:]]*#\?[[:space:]]*WaylandEnable=.*/WaylandEnable=false/' "$gdm_config"
  else
    printf '%s\n' 'WaylandEnable=false' | sudo tee -a "$gdm_config" >/dev/null
  fi
}

prompt_restart_gdm() {
  local restart_confirm

  if [[ ! -f /etc/gdm3/custom.conf ]]; then
    return
  fi

  if [[ ! -t 0 ]]; then
    echo "Non-interactive session detected, skipping gdm3 restart prompt."
    echo "Please restart your system later with: sudo systemctl restart gdm3"
    return
  fi

  echo
  echo "=================================="
  echo "IMPORTANT: System restart required"
  echo "=================================="
  echo "The display manager needs to be restarted to apply Wayland changes."
  echo "This will log you out immediately."
  echo
  read -r -p "Do you want to restart gdm3 now? (y/N): " restart_confirm

  if [[ "$restart_confirm" == "y" || "$restart_confirm" == "Y" ]]; then
    run_sudo systemctl restart gdm3
  else
    echo "Please restart your system later with: sudo systemctl restart gdm3"
  fi
}

main() {
  if ! command_exists apt-get; then
    echo "This script requires apt-get."
    exit 1
  fi

  install_xclip
  configure_gnome_ui
  configure_system_monitor_extension
  configure_power
  configure_swappiness
  install_input_mono
  install_rime
  install_albert
  install_copyq
  configure_gdm_for_copyq
  prompt_restart_gdm
}

main "$@"
