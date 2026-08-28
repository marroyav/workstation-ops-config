" Share the same fast config between Vim and Neovim.
set runtimepath^=~/.vim
set runtimepath+=~/.vim/after
let &packpath = &runtimepath

source ~/.vimrc

if filereadable(expand('~/.config/nvim/custom.vim'))
  source ~/.config/nvim/custom.vim
endif
