# Setup fzf
# ---------
if [[ ! "$PATH" == */home/neutrino/.fzf/bin* ]]; then
  PATH="${PATH:+${PATH}:}/home/neutrino/.fzf/bin"
fi

eval "$(fzf --bash)"
