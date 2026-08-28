" Modern Neovim defaults layered onto the shared Vim configuration.
if exists('g:workstation_custom_nvim_loaded')
  finish
endif
let g:workstation_custom_nvim_loaded = 1

let s:python_host = expand('~/.local/share/nvim/provider-venv/bin/python')
if executable(s:python_host)
  let g:python3_host_prog = s:python_host
endif
unlet s:python_host

let s:node_host = expand('~/.local/bin/neovim-node-host')
if executable(s:node_host)
  let g:node_host_prog = s:node_host
else
  let g:loaded_node_provider = 0
endif
unlet s:node_host

let g:loaded_perl_provider = 0
let g:loaded_ruby_provider = 0

set termguicolors
set mouse=a
set clipboard=unnamedplus
set cursorline
set signcolumn=yes
set splitbelow
set splitright
set ignorecase
set smartcase
set inccommand=split
set undofile
set undodir=~/.local/state/nvim/undo//
set updatetime=250
set timeoutlen=400
set scrolloff=5
set sidescrolloff=8
set pumheight=12
set completeopt=menu,menuone,noselect
set confirm
set autoread
if exists('+smoothscroll')
  set smoothscroll
endif
if exists('+winborder')
  set winborder=rounded
endif
set shortmess+=I
set wildignore+=*/.git/*,*/node_modules/*,*/.venv/*,*/target/*

if executable('rg')
  set grepprg=rg\ --vimgrep\ --smart-case
  set grepformat=%f:%l:%c:%m
endif

" Fast, consistent split navigation and an easy terminal-mode escape.
nnoremap <silent> <C-h> <C-w>h
nnoremap <silent> <C-j> <C-w>j
nnoremap <silent> <C-k> <C-w>k
nnoremap <silent> <C-l> <C-w>l
tnoremap <silent> <Esc><Esc> <C-\><C-n>
nnoremap <silent> <leader>tt :split<Bar>terminal<CR>
nnoremap <silent> <C-s> :update<CR>
inoremap <silent> <C-s> <C-o>:update<CR>

augroup dev_environment_defaults
  autocmd!
  autocmd TextYankPost * silent! lua vim.highlight.on_yank({ timeout = 180 })
  autocmd VimResized * wincmd =
  autocmd FileType * setlocal formatoptions-=c formatoptions-=r formatoptions-=o
augroup END

lua << EOF
vim.diagnostic.config({
  severity_sort = true,
  underline = true,
  virtual_text = { spacing = 2, source = "if_many" },
  float = { border = "rounded", source = true },
})

if vim.diagnostic.jump then
  vim.keymap.set("n", "]d", function()
    vim.diagnostic.jump({ count = 1, float = true })
  end, { desc = "Next diagnostic" })

  vim.keymap.set("n", "[d", function()
    vim.diagnostic.jump({ count = -1, float = true })
  end, { desc = "Previous diagnostic" })
else
  vim.keymap.set("n", "]d", vim.diagnostic.goto_next,
    { desc = "Next diagnostic" })
  vim.keymap.set("n", "[d", vim.diagnostic.goto_prev,
    { desc = "Previous diagnostic" })
end

vim.keymap.set("n", "<leader>d", vim.diagnostic.open_float,
  { desc = "Show line diagnostics" })
EOF
