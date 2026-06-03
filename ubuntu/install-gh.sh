#!/usr/bin/env bash
set -euo pipefail

GH_KEYRING_URL="${GH_KEYRING_URL:-https://cli.github.com/packages/githubcli-archive-keyring.gpg}"
GH_REPO_URL="${GH_REPO_URL:-https://cli.github.com/packages}"
GH_KEYRING_PATH="${GH_KEYRING_PATH:-/etc/apt/keyrings/githubcli-archive-keyring.gpg}"
GH_SOURCE_PATH="${GH_SOURCE_PATH:-/etc/apt/sources.list.d/github-cli.list}"

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

run() {
  echo
  echo "==> $*"
  "$@"
}

run_as_root() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    run "$@"
    return
  fi

  run sudo "$@"
}

package_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q '^install ok installed$'
}

install_prerequisites() {
  local packages=()

  command_exists curl || packages+=(curl)
  package_installed ca-certificates || packages+=(ca-certificates)

  if [[ "${#packages[@]}" -eq 0 ]]; then
    return
  fi

  run_as_root apt-get update
  run_as_root apt-get install -y "${packages[@]}"
}

configure_github_cli_apt_source() {
  local apt_arch
  local source_line
  local tmp_keyring

  apt_arch="$(dpkg --print-architecture)"
  source_line="deb [arch=$apt_arch signed-by=$GH_KEYRING_PATH] $GH_REPO_URL stable main"
  tmp_keyring="$(mktemp /tmp/githubcli-archive-keyring.XXXXXX.gpg)"

  trap 'rm -f "$tmp_keyring"' EXIT

  run curl -fsSL "$GH_KEYRING_URL" -o "$tmp_keyring"
  run_as_root install -d -m 0755 /etc/apt/keyrings /etc/apt/sources.list.d
  run_as_root install -m 0644 "$tmp_keyring" "$GH_KEYRING_PATH"
  printf '%s\n' "$source_line" | run_as_root tee "$GH_SOURCE_PATH" >/dev/null
}

main() {
  if command_exists gh; then
    echo "gh is already installed. Refreshing the official GitHub CLI apt source."
    gh --version | sed -n '1p'
  else
    echo "gh is not installed. Installing GitHub CLI from the official apt source."
  fi

  if ! command_exists apt-get || ! command_exists dpkg; then
    echo "This script requires an apt-based Linux distribution."
    exit 1
  fi

  install_prerequisites
  configure_github_cli_apt_source
  run_as_root apt-get update
  run_as_root apt-get install -y gh
  gh --version | sed -n '1p'
}

main "$@"
