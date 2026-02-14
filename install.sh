#!/bin/sh
set -e

DIR="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"

command_exists() {
  command -v "$@" >/dev/null 2>&1
}

# Detect OS
OS_TYPE="$(uname -s)"
case "$OS_TYPE" in
    Linux)
        if command_exists apt; then
            OS="ubuntu"
        else
            echo "Unsupported Linux distribution"
            exit 1
        fi
        ;;
        echo "Unsupported OS: $OS_TYPE"
        exit 1
        ;;
esac

# Configure Git
if ! command_exists git; then
    echo "Git is not installed. Please install Git first."
    exit 1
fi
if ! git config --global user.name >/dev/null; then
    read -p "Enter your Git user name [Li Daqian]: " git_user_name
    git_user_name="${git_user_name:-Li Daqian}"
    git config --global user.name "$git_user_name"
fi
if ! git config --global user.email >/dev/null; then
    read -p "Enter your Git user email [hi@lidaqian.me]: " git_email
    git_email="${git_email:-hi@lidaqian.me}"
    git config --global user.email "$git_email"
fi

# Install curl and wget
sudo apt update
sudo apt install -y curl wget

# Install Oh My Zsh
curl -o- https://raw.githubusercontent.com/li-daqian/dev-toolbox/main/oh-my-zsh/install.sh?$(date +%s) | sh

# Install Java
sudo apt install -y openjdk-21-jdk

# Install nvm nodejs pnpm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh | bash
nvm install --lts
npm install -g pnpm

# Install Rime
curl -o- https://raw.githubusercontent.com/li-daqian/dev-toolbox/main/rime/install.sh?$(date +%s) | sh

# Install CopyQ
sudo apt install -y software-properties-common python-software-properties
sudo add-apt-repository ppa:hluk/copyq
sudo apt update
sudo apt install -y copyq
# Add Custom Shortcuts ‘Ctrl+Shift+V‘ for CopyQ
gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/copyq-show/']"
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/copyq-show/ name 'Show CopyQ'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/copyq-show/ command 'copyq toggle'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/copyq-show/ binding '<Primary><Shift>V'
# Make CopyQ start on login
copyq config autostart true
