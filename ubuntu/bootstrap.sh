#!/usr/bin/env bash
set -euo pipefail

RAW_BASE="${RAW_BASE:-https://raw.githubusercontent.com/li-daqian/dev-toolbox/main}"
BTOP_MIN_VERSION="${BTOP_MIN_VERSION:-1.4.0}"
BTOP_OFFICIAL_DEB_URL="${BTOP_OFFICIAL_DEB_URL:-https://archive.ubuntu.com/ubuntu/pool/universe/b/btop/btop_1.4.6-2_amd64.deb}"
BTOP_RAPL_RULE_PATH="/etc/tmpfiles.d/99-btop-rapl.conf"
BTOP_RAPL_FILE="/sys/class/powercap/intel-rapl:0/energy_uj"
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
  shift 2
  local local_path="$SCRIPT_DIR/../$script_path"

  if ! command_exists "$runner"; then
    echo "$runner is required to run $script_path."
    exit 1
  fi

  if [[ -f "$local_path" ]]; then
    "$runner" "$local_path" "$@"
    return
  fi

  if ! command_exists curl; then
    echo "curl is required to download $script_path."
    exit 1
  fi

  curl -fsSL "$RAW_BASE/$script_path?$(date +%s)" | "$runner" -s -- "$@"
}

install_base_packages() {
  run_sudo apt-get update
  run_sudo apt-get install -y ca-certificates curl wget git unzip fontconfig software-properties-common gpg
}

configure_git() {
  local git_user_name
  local git_email

  if ! git config --global user.name >/dev/null 2>&1; then
    if [[ -t 0 ]]; then
      read -r -p "Enter your Git user name [Li Daqian]: " git_user_name
      git_user_name="${git_user_name:-Li Daqian}"
      git config --global user.name "$git_user_name"
    else
      echo "Git user.name is not configured and no interactive input is available. Skipping Git user name setup."
    fi
  fi

  if ! git config --global user.email >/dev/null 2>&1; then
    if [[ -t 0 ]]; then
      read -r -p "Enter your Git user email [hi@lidaqian.me]: " git_email
      git_email="${git_email:-hi@lidaqian.me}"
      git config --global user.email "$git_email"
    else
      echo "Git user.email is not configured and no interactive input is available. Skipping Git user email setup."
    fi
  fi
}

install_apt_command() {
  local command_name="$1"
  shift

  if command_exists "$command_name"; then
    echo "$command_name is already installed. Skipping."
    return
  fi

  run_sudo apt-get install -y "$@"
}

dpkg_version_ge() {
  dpkg --compare-versions "$1" ge "$2"
}

get_apt_candidate_version() {
  apt-cache policy "$1" | awk '/Candidate:/ { print $2; exit }'
}

get_installed_package_version() {
  dpkg-query -W -f='${Version}' "$1" 2>/dev/null || true
}

configure_btop_config() {
  local config_dir="$HOME/.config/btop"
  local config_file="$config_dir/btop.conf"

  mkdir -p "$config_dir"

  if [[ ! -f "$config_file" ]]; then
    if ! command_exists btop; then
      echo "btop is not installed, skipping btop config generation."
      return
    fi

    btop --default-config >"$config_file"
  fi

  if grep -q '^show_cpu_watts = ' "$config_file"; then
    sed -i 's/^show_cpu_watts = .*/show_cpu_watts = true/' "$config_file"
  else
    printf '%s\n' 'show_cpu_watts = true' >>"$config_file"
  fi

  if grep -q '^show_battery_watts = ' "$config_file"; then
    sed -i 's/^show_battery_watts = .*/show_battery_watts = false/' "$config_file"
  else
    printf '%s\n' 'show_battery_watts = false' >>"$config_file"
  fi
}

configure_btop_watts_support() {
  configure_btop_config

  if [[ ! -e "$BTOP_RAPL_FILE" ]]; then
    echo "$BTOP_RAPL_FILE not found, skipping CPU wattage permission configuration."
    return
  fi

  printf '%s\n' "z $BTOP_RAPL_FILE 0444 root root - -" | run_sudo tee "$BTOP_RAPL_RULE_PATH" >/dev/null
  run_sudo systemd-tmpfiles --create "$BTOP_RAPL_RULE_PATH"
}

install_btop() {
  local installed_version
  local candidate_version
  local tmp_deb

  installed_version="$(get_installed_package_version btop)"
  if [[ -n "$installed_version" ]] && dpkg_version_ge "$installed_version" "$BTOP_MIN_VERSION"; then
    echo "btop $installed_version is already installed. Skipping package upgrade."
    configure_btop_watts_support
    return
  fi

  candidate_version="$(get_apt_candidate_version btop)"
  if [[ -n "$candidate_version" ]] && [[ "$candidate_version" != "(none)" ]] && dpkg_version_ge "$candidate_version" "$BTOP_MIN_VERSION"; then
    run_sudo apt-get install -y btop
    configure_btop_watts_support
    return
  fi

  if ! command_exists curl; then
    echo "curl is required to download an official btop package."
    exit 1
  fi

  tmp_deb="$(mktemp /tmp/btop.XXXXXX.deb)"
  curl -fsSL "$BTOP_OFFICIAL_DEB_URL" -o "$tmp_deb"
  run_sudo apt-get install -y "$tmp_deb"
  rm -f "$tmp_deb"
  configure_btop_watts_support
}

install_oh_my_zsh() {
  if [[ -d "$HOME/.oh-my-zsh" ]]; then
    echo "Oh My Zsh is already installed. Skipping."
    return
  fi

  run_repo_script "oh-my-zsh/install.sh" sh
}

install_sdkman() {
  if [[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]]; then
    echo "SDKMAN is already installed. Skipping SDKMAN installation."
    return
  fi

  echo "SDKMAN is not installed. Installing SDKMAN ..."
  curl -fsSL "https://get.sdkman.io" | bash
}

sdk_command_exists() {
  local command_name="$1"

  if [[ ! -s "$HOME/.sdkman/bin/sdkman-init.sh" ]]; then
    return 1
  fi

  bash -lc "source \"$HOME/.sdkman/bin/sdkman-init.sh\" && command -v $command_name >/dev/null 2>&1"
}

install_sdk_package() {
  local candidate="$1"
  local command_name="$2"

  if command_exists "$command_name" || sdk_command_exists "$command_name"; then
    echo "$candidate is already installed. Skipping."
    return
  fi

  install_sdkman
  echo "Installing $candidate via SDKMAN ..."
  bash -lc "source \"$HOME/.sdkman/bin/sdkman-init.sh\" && sdk install $candidate"
}

install_nvm_toolchain() {
  if [[ ! -s "$HOME/.nvm/nvm.sh" ]]; then
    echo "nvm is not installed. Installing nvm ..."
    curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh" | bash
  else
    echo "nvm is already installed. Skipping nvm installation."
  fi

  bash -lc "source \"$HOME/.nvm/nvm.sh\" && command -v node >/dev/null 2>&1 || nvm install --lts"
  bash -lc "source \"$HOME/.nvm/nvm.sh\" && command -v pnpm >/dev/null 2>&1 || npm install -g pnpm"

  if [[ -x "$HOME/.bun/bin/bun" ]]; then
    echo "bun is already installed. Skipping bun installation."
    return
  fi

  echo "bun is not installed. Installing bun ..."
  curl -fsSL https://bun.sh/install | bash
}

install_rust() {
  if command_exists rustup; then
    echo "Rust is already installed. Skipping Rust installation."
    return
  fi

  echo "Rust is not installed. Installing Rust ..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
}

install_docker() {
  if command_exists docker; then
    echo "Docker is already installed. Skipping Docker installation."
    return
  fi

  run_repo_script "docker/install-ubuntu.sh" sh
}

install_github_cli() {
  run_repo_script "ubuntu/install-gh.sh" bash
}

cleanup_journal() {
  if ! command_exists journalctl; then
    echo "journalctl not found, skipping log cleanup."
    return
  fi

  run_sudo journalctl --vacuum-time=7d
}

main() {
  if ! command_exists apt-get; then
    echo "This script requires apt-get."
    exit 1
  fi

  install_base_packages
  configure_git
  install_github_cli
  install_btop
  install_apt_command neofetch neofetch
  install_oh_my_zsh
  install_sdkman
  install_sdk_package java java
  install_sdk_package maven mvn
  install_nvm_toolchain
  install_rust
  install_docker
  run_repo_script "ubuntu/bootstrap-desktop.sh" bash
  cleanup_journal
}

if [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then
  main "$@"
fi
