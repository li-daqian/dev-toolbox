#!/bin/sh
set -eu

DIR="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"

command_exists() {
  command -v "$@" >/dev/null 2>&1
}

add_custom_shortcut() {
    local shortcut_id="$1"
    local name="$2"
    local command="$3"
    local binding="$4"
    
    local shortcut_path="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/$shortcut_id/"
    local current=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings | sed "s/@as //")
    
    if echo "$current" | grep -q "$shortcut_path"; then
        echo "$name shortcut already configured"
    else
        if [ "$current" = "[]" ]; then
            new_list="['$shortcut_path']"
        else
            new_list=$(echo "$current" | sed "s|]$|, '$shortcut_path']|")
        fi
        gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$new_list"
    fi
    
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/$shortcut_id/ name "$name"
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/$shortcut_id/ command "$command"
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/$shortcut_id/ binding "$binding"
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
# Make Dock click action to minimize when app is focused
gsettings set org.gnome.shell.extensions.dash-to-dock click-action 'minimize'

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

# Install btop
if ! command_exists btop; then
    echo "btop is not installed. Installing btop ..."
    sudo apt install -y btop
else
    echo "btop is already installed. Skipping btop installation."
fi

# Install neofetch
if ! command_exists neofetch; then
    echo "Neofetch is not installed. Installing Neofetch ..."
    sudo apt install -y neofetch
else
    echo "Neofetch is already installed. Skipping Neofetch installation."
fi

# Install Oh My Zsh
if ! command_exists zsh; then
    echo "Zsh is not installed. Installing Zsh ..."
    curl -fsSL "https://raw.githubusercontent.com/li-daqian/dev-toolbox/main/oh-my-zsh/install.sh?$(date +%s)" | sh
fi

# Install Java
if ! command_exists sdk; then
    echo "SDKMAN is not installed. Installing SDKMAN and Java ..."
    curl -fsSL "https://get.sdkman.io" | bash
else
    echo "SDKMAN is already installed. Skipping SDKMAN and Java installation."
fi
if ! command_exists java; then
    zsh -c "source ~/.zshrc && sdk install java"
else
    echo "Java is already installed. Skipping Java installation."
fi

# Install nvm nodejs pnpm by zsh
if ! command_exists nvm; then
    echo "nvm is not installed. Installing nvm, nodejs and pnpm ..."
    curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh" | bash
    zsh -c "source ~/.zshrc && nvm install --lts && npm install -g pnpm"
    # bun
    zsh -c "source ~/.zshrc && curl -fsSL https://bun.sh/install | bash"
fi

# Install Rust
if ! command_exists rustup; then
    echo "Rust is not installed. Installing Rust ..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
else
    echo "Rust is already installed. Skipping Rust installation."
fi

# Install Docker
if ! command_exists docker; then
    echo "Docker is not installed. Installing Docker ..."
    curl -fsSL "https://raw.githubusercontent.com/li-daqian/dev-toolbox/main/docker/install-ubuntu.sh?$(date +%s)" | sh
else
    echo "Docker is already installed. Skipping Docker installation."
fi

# Install Rime
curl -fsSL "https://raw.githubusercontent.com/li-daqian/dev-toolbox/main/rime/install.sh?$(date +%s)" | sh

# Install Albert
if ! command_exists albert; then
    echo "Albert is not installed. Installing Albert ..."
    echo 'deb http://download.opensuse.org/repositories/home:/manuelschneid3r/xUbuntu_24.04/ /' | sudo tee /etc/apt/sources.list.d/home:manuelschneid3r.list
    curl -fsSL https://download.opensuse.org/repositories/home:manuelschneid3r/xUbuntu_24.04/Release.key | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/home_manuelschneid3r.gpg > /dev/null
    sudo apt update
    sudo apt install -y albert
    # Make Albert start on login
    mkdir -p ~/.config/autostart
    cat > ~/.config/autostart/albert.desktop <<EOL
[Desktop Entry]
Type=Application
Exec=albert
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=Albert
Comment=Start Albert on login
EOL
    # Add Custom Shortcuts ‘Alt+Space‘ for Albert
    add_custom_shortcut "albert-show" "Show Albert" "albert toggle" "<Alt>space"
else
    echo "Albert is already installed. Skipping Albert installation."
fi

# Install CopyQ
sudo apt install -y software-properties-common
sudo add-apt-repository -y ppa:hluk/copyq
sudo apt update
sudo apt install -y copyq
# Add Custom Shortcuts Command+V‘ for CopyQ
add_custom_shortcut "copyq-show" "Show CopyQ" "copyq toggle" "<Super>v"
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
