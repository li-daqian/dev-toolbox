#!/bin/sh
set -e

DIR="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"

command_exists() {
  command -v "$@" >/dev/null 2>&1
}

install_packages() {
    case "$OS" in
        ubuntu|debian)
            sudo apt update
            sudo apt install -y ibus-rime rime-data-double-pinyin
            ;;
        centos|rhel|fedora)
            sudo yum install -y ibus-rime rime-data-double-pinyin
            ;;
        *)
            echo "Unsupported OS: $OS"
            exit 1
            ;;
    esac
}

# Detect OS
OS_TYPE="$(uname -s)"
case "$OS_TYPE" in
    Linux)
        if command_exists apt; then
            OS="ubuntu"
        elif command_exists yum; then
            OS="centos"
        else
            echo "Unsupported Linux distribution"
            exit 1
        fi
        ;;
    *)
        echo "Unsupported OS: $OS_TYPE"
        exit 1
        ;;
esac

install_packages

# Install Rime configuration
RIME_CONFIG_DIR="$HOME/.config/ibus/rime"
mkdir -p "$RIME_CONFIG_DIR"
echo "$(curl -o-https://raw.githubusercontent.com/li-daqian/dev-toolbox/main/rime/default.custom.yaml)" > "$RIME_CONFIG_DIR/default.custom.yaml"
echo "$(curl -o-https://raw.githubusercontent.com/li-daqian/dev-toolbox/main/rime/double_pinyin_flypy.schema.yaml)" > "$RIME_CONFIG_DIR/double_pinyin_flypy.schema.yaml"
echo "$(curl -o-https://raw.githubusercontent.com/li-daqian/dev-toolbox/main/rime/ibus_rime.custom.yaml)" > "$RIME_CONFIG_DIR/ibus_rime.custom.yaml"
