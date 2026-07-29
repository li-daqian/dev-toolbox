#!/usr/bin/env bash
set -euo pipefail

ALBERT_REPOSITORY_URL="https://download.opensuse.org/repositories/home:/manuelschneid3r/xUbuntu_24.04"
ALBERT_SOURCE_FILE="/etc/apt/sources.list.d/home:manuelschneid3r.list"
ALBERT_KEY_FILE="/etc/apt/trusted.gpg.d/home_manuelschneid3r.gpg"
ALBERT_CONFIG_DIR="$HOME/.config/albert"
ALBERT_CONFIG_FILE="$ALBERT_CONFIG_DIR/config"
ALBERT_AUTOSTART_DIR="$HOME/.config/autostart"
ALBERT_AUTOSTART_FILE="$ALBERT_AUTOSTART_DIR/albert.desktop"

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

run() {
  echo
  echo "==> $*"
  "$@"
}

run_sudo() {
  if [[ -n "${SUDO_ASKPASS:-}" ]]; then
    run sudo -A "$@"
  else
    run sudo "$@"
  fi
}

sudo_tee() {
  if [[ -n "${SUDO_ASKPASS:-}" ]]; then
    sudo -A tee "$@"
  else
    sudo tee "$@"
  fi
}

require_command() {
  local command_name="$1"

  if ! command_exists "$command_name"; then
    echo "$command_name is required to install Albert." >&2
    exit 1
  fi
}

validate_platform() {
  if [[ ! -r /etc/os-release ]]; then
    echo "Unable to detect the operating system." >&2
    exit 1
  fi

  # shellcheck disable=SC1091
  source /etc/os-release
  if [[ "${ID:-}" != "ubuntu" || "${VERSION_ID:-}" != "24.04" ]]; then
    echo "This installer supports Ubuntu 24.04 only." >&2
    exit 1
  fi
}

set_ini_value() {
  local file="$1"
  local section="$2"
  local key="$3"
  local value="$4"
  local tmp_file

  mkdir -p "$(dirname "$file")"
  touch "$file"
  tmp_file="$(mktemp)"

  awk -v section="$section" -v key="$key" -v value="$value" '
    BEGIN {
      in_section = 0
      section_found = 0
      key_written = 0
    }

    /^\[/ {
      if (in_section && !key_written) {
        print key "=" value
        key_written = 1
      }

      in_section = ($0 == "[" section "]")
      if (in_section) {
        section_found = 1
      }

      print
      next
    }

    {
      if (in_section && index($0, key "=") == 1) {
        if (!key_written) {
          print key "=" value
          key_written = 1
        }
        next
      }

      print
    }

    END {
      if (in_section && !key_written) {
        print key "=" value
      }

      if (!section_found) {
        if (NR > 0) {
          print ""
        }
        print "[" section "]"
        print key "=" value
      }
    }
  ' "$file" >"$tmp_file"

  mv "$tmp_file" "$file"
}

has_google_chrome_profile() {
  [[ -d "$HOME/.config/google-chrome/Default" ]]
}

configure_albert() {
  local -a enabled_plugins=(
    application
    applications
    calculator_qalculate
    commandline
    datetime
    python
    python.emoji
    python.vscode_projects
    websearch
  )
  local plugin

  mkdir -p "$ALBERT_AUTOSTART_DIR"
  cat >"$ALBERT_AUTOSTART_FILE" <<'EOF'
[Desktop Entry]
Type=Application
Exec=albert
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=Albert
Comment=Start Albert on login
EOF

  mkdir -p "$ALBERT_CONFIG_DIR"
  set_ini_value "$ALBERT_CONFIG_FILE" "General" "hotkey" "Alt+Space"
  set_ini_value "$ALBERT_CONFIG_FILE" "widgetsboxmodel" "disable_input_method" "false"

  if command_exists google-chrome || command_exists google-chrome-stable || has_google_chrome_profile; then
    set_ini_value "$ALBERT_CONFIG_FILE" "chromium" "profile_path" "$HOME/.config/google-chrome/Default"
    set_ini_value "$ALBERT_CONFIG_FILE" "chromium" "enabled" "true"
  fi

  for plugin in "${enabled_plugins[@]}"; do
    set_ini_value "$ALBERT_CONFIG_FILE" "$plugin" "enabled" "true"
  done
}

main() {
  validate_platform
  require_command apt-get
  require_command curl
  require_command gpg
  require_command sudo

  if ! command_exists albert; then
    echo "Albert is not installed. Installing Albert ..."

    printf '%s\n' "deb $ALBERT_REPOSITORY_URL/ /" | sudo_tee "$ALBERT_SOURCE_FILE" >/dev/null
    curl -fsSL "$ALBERT_REPOSITORY_URL/Release.key" | gpg --dearmor | sudo_tee "$ALBERT_KEY_FILE" >/dev/null
  fi

  if ! command_exists albert || ! command_exists xdotool; then
    run_sudo apt-get update
    run_sudo apt-get install -y albert xdotool
  else
    echo "Albert and xdotool are already installed. Skipping package installation."
  fi

  configure_albert
  echo "Albert installation and configuration completed."
}

main "$@"
