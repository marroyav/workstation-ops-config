# shellcheck shell=bash
# Interactive Bash productivity defaults. This file is sourced by ~/.bashrc.
export EDITOR=nvim
export VISUAL=nvim
export GIT_EDITOR=nvim
export BROWSER=brave-browser
export PAGER=less
export LESS='-FRX'

HISTSIZE=100000
HISTFILESIZE=200000
HISTTIMEFORMAT='%F %T  '
shopt -s histappend cmdhist lithist checkwinsize

alias l='eza --group-directories-first --icons=never'
alias ll='eza -lah --git --group-directories-first --icons=never'
alias la='eza -a --group-directories-first --icons=never'
alias lt='eza --tree --level=2 --group-directories-first --icons=never'
alias v='nvim'
alias lg='lazygit'
alias top='btop'

mkcd() {
  if [ "$#" -ne 1 ]; then
    printf 'usage: mkcd DIRECTORY\n' >&2
    return 2
  fi
  mkdir -p -- "$1" || return
  cd -- "$1" || return
}

fcd() {
  local selected_directory
  selected_directory="$(fd --type d --hidden --exclude .git . "${1:-.}" |
    fzf --height=70% --layout=reverse --border --preview 'eza --tree --level=2 --color=always --icons=never {} | head -200')" || return
  cd -- "$selected_directory" || return
}

export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_DEFAULT_OPTS='--height=70% --layout=reverse --border --info=inline --cycle'
export FZF_CTRL_T_OPTS="--walker-skip .git,node_modules,target,.venv --preview 'bat --style=numbers --color=always --line-range=:500 {}' --bind 'ctrl-/:change-preview-window(down|hidden|)'"
export FZF_ALT_C_OPTS="--walker-skip .git,node_modules,target,.venv --preview 'eza --tree --level=2 --color=always --icons=never {} | head -200'"

_fzf_compgen_path() {
  fd --hidden --follow --exclude .git . "$1"
}

_fzf_compgen_dir() {
  fd --type d --hidden --follow --exclude .git . "$1"
}

if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init bash)"
fi

if command -v direnv >/dev/null 2>&1; then
  eval "$(direnv hook bash)"
fi

_dev_history_sync() {
  builtin history -a
  builtin history -n
}
PROMPT_COMMAND="_dev_history_sync${PROMPT_COMMAND:+;$PROMPT_COMMAND}"

if command -v starship >/dev/null 2>&1 && [ "${TERM:-dumb}" != dumb ]; then
  eval "$(starship init bash)"
fi
