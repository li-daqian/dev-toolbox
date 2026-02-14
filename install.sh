#!/bin/sh
set -eu

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
    *)
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

# Configure UI
# Make Dock position to bottom
gsettings set org.gnome.shell.extensions.dash-to-dock dock-position 'BOTTOM'
# Make Dock not auto-hide
gsettings set org.gnome.shell.extensions.dash-to-dock dock-fixed true
# Desktop Icons don't show Home Folder
gsettings set org.gnome.shell.extensions.ding show-home false
# Make Apperance style to Dark
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
# Make large text on Accessibility's seeing section
gsettings set org.gnome.desktop.interface text-scaling-factor 1.2

# Install 'Input Mono' font
if ! fc-list | grep -q "Input Mono"; then
    echo "Input Mono font is not installed. Installing Input Mono font ..."
    mkdir -p ~/.local/share/fonts
    curl -fsSL "https://input.djr.com/build/?fontSelection=whole&a=0&g=0&i=0&l=0&zero=0&asterisk=0&braces=0&preset=default&line-height=1.2&accept=I+do&email=" -o /tmp/Input-Font.zip
    unzip -o /tmp/Input-Font.zip -d /tmp/Input-Font
    cp /tmp/Input-Font/**/InputMono-*.ttf ~/.local/share/fonts/
    rm -rf /tmp/Input-Font /tmp/Input-Font.zip
    fc-cache -f -v
fi

# Install Oh My Zsh
if ! command_exists zsh; then
    echo "Zsh is not installed. Installing Zsh ..."
    curl -fsSL  https://raw.githubusercontent.com/li-daqian/dev-toolbox/main/oh-my-zsh/install.sh?$(date +%s) | sh
fi

# Install Java
sudo apt install -y openjdk-21-jdk

# Install nvm nodejs pnpm by zsh
if ! command_exists nvm; then
    echo "nvm is not installed. Installing nvm, nodejs and pnpm ..."
    curl -fsSL  https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh | bash
    zsh -c "source ~/.zshrc && nvm install --lts && npm install -g pnpm"
fi

# Install Rime
curl -fsSL  https://raw.githubusercontent.com/li-daqian/dev-toolbox/main/rime/install.sh?$(date +%s) | sh

# Install CopyQ
sudo apt install -y software-properties-common
sudo add-apt-repository -y ppa:hluk/copyq
sudo apt update
sudo apt install -y copyq
# Add Custom Shortcuts ‘Ctrl+Shift+V‘ for CopyQ
gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/copyq-show/']"
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/copyq-show/ name 'Show CopyQ'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/copyq-show/ command 'copyq toggle'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/copyq-show/ binding '<Primary><Shift>V'
# Make CopyQ start on login
copyq config autostart true
# Make CopyQ tray_item_paste work, need make 'Wayland' to 'X11' in /etc/gdm3/custom.conf and reboot
sudo sed -i 's/#WaylandEnable=false/WaylandEnable=false/g' /etc/gdm3/custom.conf 
# ⚠️ Warn user about restart requirement
# ⚠️ Make this end of the script
echo ""
echo "=================================="
echo "⚠️  IMPORTANT: System restart required"
echo "=================================="
echo "The display manager needs to be restarted to apply Wayland changes."
echo "This will log you out immediately."
echo ""
read -p "Do you want to restart now? (y/N): " restart_confirm
if [ "$restart_confirm" = "y" ] || [ "$restart_confirm" = "Y" ]; then
    sudo systemctl restart gdm3
else
    echo "Please restart your system later with: sudo systemctl restart gdm3"
fi
