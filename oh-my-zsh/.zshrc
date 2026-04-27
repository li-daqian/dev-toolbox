export ZSH=$HOME/.oh-my-zsh
# git clone https://github.com/denysdovhan/spaceship-prompt.git "$ZSH_CUSTOM/themes/spaceship-prompt" --depth=1
# ln -s "$ZSH_CUSTOM/themes/spaceship-prompt/spaceship.zsh-theme" "$ZSH_CUSTOM/themes/spaceship.zsh-theme"
ZSH_THEME="spaceship"

# git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
# git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
# git clone https://github.com/agkozak/zsh-z $ZSH_CUSTOM/plugins/zsh-z
plugins=(
  git
  zsh-autosuggestions
  zsh-syntax-highlighting
  zsh-z
)

# Disable MAGIC_FUNCTIONS, If enalbed will append '\' before '$' and '(' when pasting command, which is annoying.
DISABLE_MAGIC_FUNCTIONS=true

# https://ohmyz.sh/
source $ZSH/oh-my-zsh.sh

# alias
alias update="sudo apt update && sudo apt install --only-upgrade"
alias update-chrome="update google-chrome-stable"

# Work around Codex creating an empty .codex file in WSL sandboxed projects.
codex() {
  if [ -f .codex ] && [ ! -s .codex ]; then
    rm -f .codex
  fi

  mkdir -p .codex || return
  command codex "$@"
}
