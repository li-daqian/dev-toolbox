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
            sudo apt install -y zsh git curl wget
            ;;
        centos|rhel|fedora)
            sudo yum install -y zsh git curl wget
            ;;
        macos)
            if ! command_exists brew; then
                echo "Homebrew is not installed. Installing Homebrew first..."
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            fi
            brew install zsh git curl wget
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
    Darwin)
        OS="macos"
        ;;
    *)
        echo "Unsupported OS: $OS_TYPE"
        exit 1
        ;;
esac

install_packages

# Install Oh My Zsh
if command_exists curl; then
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh | sed '/exec zsh -l/d')"
else
  sh -c "$(wget -O- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh | sed '/exec zsh -l/d')"
fi

# Install spaceship theme
ZSH_CUSTOM=${ZSH_CUSTOM:-~/.oh-my-zsh/custom}
git clone https://github.com/denysdovhan/spaceship-prompt.git "$ZSH_CUSTOM/themes/spaceship-prompt" --depth=1
ln -sf "$ZSH_CUSTOM/themes/spaceship-prompt/spaceship.zsh-theme" "$ZSH_CUSTOM/themes/spaceship.zsh-theme"

# Install plugins
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM}/plugins/zsh-autosuggestions --depth=1
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting --depth=1
git clone https://github.com/agkozak/zsh-z ${ZSH_CUSTOM}/plugins/zsh-z --depth=1

# Download custom .zshrc
echo "$(curl -fsSL https://raw.githubusercontent.com/li-daqian/dev-toolbox/main/oh-my-zsh/.zshrc)" > ~/.zshrc

# Switch to zsh
exec zsh -l
