" Share the same fast config between Vim and Neovim.
set runtimepath^=~/.vim
set runtimepath+=~/.vim/after
let &packpath = &runtimepath

source ~/.vimrc
