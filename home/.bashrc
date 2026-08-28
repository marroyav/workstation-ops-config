# Minimal interactive bash config for WSL work.
case $- in
  *i*) ;;
  *) return ;;
esac

export HISTCONTROL=ignoreboth:erasedups
export HISTSIZE=5000
export HISTFILESIZE=10000
shopt -s histappend
shopt -s checkwinsize

PROMPT_DIRTRIM=3
if [ -t 1 ]; then
  PS1='\[\e[1;34m\]\u@\h\[\e[0m\]:\[\e[36m\]\w\[\e[0m\]\[\e[1;34m\]\$\[\e[0m\] '
else
  PS1='\u@\h:\w\$ '
fi

if [ -d "$HOME/.local/bin" ]; then
  PATH="$HOME/.local/bin:$PATH"
fi

if [ -x /usr/bin/dircolors ]; then
  eval "$(dircolors -b)"
  alias ls='ls --color=auto'
fi

if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

alias ll='ls -lh'
alias la='ls -A'

if [ -f "$HOME/.fzf.bash" ]; then
  . "$HOME/.fzf.bash"
fi

use_xilinx_2024_1() {
  local root="$HOME/tools/Xilinx"

  if [ ! -f "$root/Vivado/2024.1/settings64.sh" ]; then
    echo "Vivado 2024.1 is not installed under $root." >&2
    return 1
  fi

  # shellcheck disable=SC1091
  . "$root/Vivado/2024.1/settings64.sh"

  if [ -f "$root/Vitis/2024.1/settings64.sh" ]; then
    # shellcheck disable=SC1091
    . "$root/Vitis/2024.1/settings64.sh"
  fi
}

if [ -r "$HOME/.cargo/env" ]; then
  . "$HOME/.cargo/env"
fi

# Wayland-first WSLg defaults and interactive productivity helpers.
if [ -r "$HOME/.config/shell/wayland-wslg.sh" ]; then
  . "$HOME/.config/shell/wayland-wslg.sh"
fi
if [ -r "$HOME/.config/shell/productivity.bash" ]; then
  . "$HOME/.config/shell/productivity.bash"
fi
