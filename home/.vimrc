" Fast, portable Vim/Neovim config for daily development.
scriptencoding utf-8
set nocompatible

let mapleader = " "
let maplocalleader = ","

filetype plugin indent on
syntax enable

" Editing defaults.
set encoding=utf-8
set hidden
set autoread
set confirm
set backspace=indent,eol,start
set mouse=a

" Two-space indentation by default.
set expandtab
set tabstop=2
set softtabstop=2
set shiftwidth=2
set smarttab
set shiftround
set autoindent
set smartindent

" UI optimized for scanning code.
set number
set relativenumber
set cursorline
set ruler
set showcmd
set laststatus=2
set splitbelow
set splitright
set scrolloff=5
set sidescrolloff=8
set nowrap
set linebreak
set list
set listchars=tab:>-,trail:.,extends:>,precedes:<,nbsp:+
set foldmethod=indent
set foldlevelstart=99
set pumheight=12
set completeopt=menuone,noinsert,noselect
set shortmess+=c
set timeoutlen=500
set updatetime=250

if exists('&termguicolors')
  set termguicolors
endif
if exists('&signcolumn')
  set signcolumn=yes
endif
if exists('&wildignorecase')
  set wildignorecase
endif

" Search and command completion.
set ignorecase
set smartcase
set incsearch
set hlsearch
set wildmenu
set wildmode=longest:full,full
set path+=**
set suffixesadd=.c,.cc,.cpp,.h,.hpp,.py,.sh,.md,.txt
set wildignore+=*/.git/*,*/node_modules/*,*/.venv/*,*/venv/*,*/__pycache__/*
set wildignore+=*.o,*.obj,*.pyc,*.so,*.dll,*.zip,*.tar,*.gz

if executable('rg')
  set grepprg=rg\ --vimgrep\ --smart-case\ --hidden\ --glob\ !.git
  set grepformat=%f:%l:%c:%m
endif

" Durable local state.
set undofile
set undodir=~/.vim/undo//
set directory=~/.vim/swap//
set backupdir=~/.vim/backup//
set backup
set writebackup
set viewoptions=folds,cursor,curdir

for s:dir in ['~/.vim/undo', '~/.vim/swap', '~/.vim/backup']
  if !isdirectory(expand(s:dir))
    call mkdir(expand(s:dir), 'p')
  endif
endfor

" Netrw file explorer.
let g:netrw_banner = 0
let g:netrw_liststyle = 3
let g:netrw_browse_split = 4
let g:netrw_altv = 1
let g:netrw_winsize = 25

" Status line without plugin overhead.
set statusline=%f
set statusline+=%m%r%h%w
set statusline+=\ [%{&filetype==#''?'text':&filetype}]
set statusline+=\ [%{&fileformat}]
set statusline+=%=
set statusline+=%l:%c\ %p%%

" Use the desktop clipboard for normal yanks, visual yanks, and puts.
if has('clipboard')
  set clipboard^=unnamedplus
endif

function! s:copy_yank_to_system_clipboard() abort
  if !exists('v:event') || get(v:event, 'operator', '') !=# 'y'
    return
  endif

  let l:text = join(get(v:event, 'regcontents', []), "\n")
  if get(v:event, 'regtype', '') ==# 'V'
    let l:text .= "\n"
  endif

  if executable('wl-copy') && !empty($WAYLAND_DISPLAY)
    call system('wl-copy', l:text)
  elseif executable('xclip') && !empty($DISPLAY)
    call system('xclip -selection clipboard', l:text)
  elseif executable('xsel') && !empty($DISPLAY)
    call system('xsel --clipboard --input', l:text)
  endif
endfunction

" Project search helper.
function! s:grep(query) abort
  if empty(a:query)
    return
  endif
  execute 'silent grep! ' . a:query
  copen
endfunction

command! -nargs=+ Rg call s:grep(<q-args>)
command! TrimWhitespace keeppatterns %s/\s\+$//e

augroup efficient_dev
  autocmd!
  autocmd TextYankPost * call s:copy_yank_to_system_clipboard()
  autocmd BufReadPost *
        \ if line("'\"") > 1 && line("'\"") <= line("$") |
        \   execute 'normal! g`"' |
        \ endif
  autocmd FileType * setlocal formatoptions-=c formatoptions-=r formatoptions-=o
  autocmd FileType make setlocal noexpandtab tabstop=8 softtabstop=0 shiftwidth=8
augroup END

" Fast navigation and editing.
nnoremap <Space> <Nop>
nnoremap <leader>w :write<CR>
nnoremap <leader>q :quit<CR>
nnoremap <leader>x :xit<CR>
nnoremap <leader>h :nohlsearch<CR>
nnoremap <leader>e :Lexplore<CR>
nnoremap <leader>f :find<Space>
nnoremap <leader>b :ls<CR>:buffer<Space>
nnoremap <leader>g :Rg<Space>
nnoremap <leader>* :Rg <C-r><C-w><CR>
nnoremap <leader>c :copen<CR>
nnoremap <leader>n :cnext<CR>
nnoremap <leader>p :cprevious<CR>
nnoremap <leader>m :make<CR>:copen<CR>
nnoremap <leader>s :split<CR>
nnoremap <leader>v :vsplit<CR>
nnoremap <leader>tw :TrimWhitespace<CR>
nnoremap Y y$

nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l

vnoremap < <gv
vnoremap > >gv
xnoremap J :move '>+1<CR>gv=gv
xnoremap K :move '<-2<CR>gv=gv

if has('terminal') || has('nvim')
  nnoremap <leader>t :terminal<CR>
  tnoremap <Esc><Esc> <C-\><C-n>
endif

" Better built-in matching for %, especially in HTML/XML.
silent! packadd matchit

" Optional private overrides.
if filereadable(expand('~/.vimrc.local'))
  source ~/.vimrc.local
endif
