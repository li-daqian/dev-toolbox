#!/usr/bin/env bash
set -euo pipefail

RAW_BASE="${RAW_BASE:-https://raw.githubusercontent.com/li-daqian/dev-toolbox/main}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

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
    read -r -p "Enter your Git user name [Li Daqian]: " git_user_name
    git_user_name="${git_user_name:-Li Daqian}"
    git config --global user.name "$git_user_name"
  fi

  if ! git config --global user.email >/dev/null 2>&1; then
    read -r -p "Enter your Git user email [hi@lidaqian.me]: " git_email
    git_email="${git_email:-hi@lidaqian.me}"
    git config --global user.email "$git_email"
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

cleanup_journal() {
  if ! command_exists journalctl; then
    echo "journalctl not found, skipping log cleanup."
    return
  fi

  run_sudo journalctl --vacuum-time=7d
}

install_global_agent_charter() {
  run_repo_script "scripts/install-global-agent-charter.sh" bash --apply
}

main() {
  if ! command_exists apt-get; then
    echo "This script requires apt-get."
    exit 1
  fi

  install_base_packages
  configure_git
  install_apt_command btop btop
  install_apt_command neofetch neofetch
  install_oh_my_zsh
  install_sdkman
  install_sdk_package java java
  install_sdk_package maven mvn
  install_nvm_toolchain
  install_rust
  install_docker
  run_repo_script "ubuntu/bootstrap-desktop.sh" bash
  install_global_agent_charter
  cleanup_journal
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
