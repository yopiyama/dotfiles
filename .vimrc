set nobackup
set noswapfile
set autoread
set hidden
set showcmd

set number
set title
set ambiwidth=double
set tabstop=4
set shiftwidth=4
set cursorline
set virtualedit=onemore
set whichwrap=b,s,[,],<,>
set backspace=indent,eol,start
set smartindent
set showmatch
set laststatus=2
set wildmode=list:longest
nnoremap j gj
nnoremap k gk

set fenc=utf-8

set ignorecase
set smartcase
set incsearch
set wrapscan
set hlsearch
nmap <Esc><Esc> :nohlsearch<CR><Esc>

if has("syntax")
	syntax on
endif

set list
set listchars=tab:--,eol:~,extends:>,precedes:<,trail:~

autocmd BufWritePre * :%s/\s\+$//ge

set visualbell

colorscheme molokai
