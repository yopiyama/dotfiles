set autoread
set hidden
set showcmd

set number
set title
set ambiwidth=double
"tabは4タブ
set tabstop=4
set shiftwidth=4
set smartindent
set autoindent

set cursorline
set virtualedit=onemore
"行頭で左を押したら前の行末に行末で右を押したら次の行頭に
set whichwrap=b,s,[,],<,>,h,l

" 余裕を持ってスクロール
set scrolloff=4

set backspace=indent,eol,start
set showmatch
set laststatus=2
set wildmode=list:longest
"確かgjとかで下の行のその列にそのまま動けるようになるやつ
nnoremap j gj
nnoremap k gk
nnoremap <Down> gj
nnoremap <Up>   gk


" モードによってカーソルの形状を変える．
if has('vim_starting')
    " 挿入モード時に非点滅の縦棒タイプのカーソル
    let &t_SI .= "\e[6 q"
    " ノーマルモード時に非点滅のブロックタイプのカーソル
    let &t_EI .= "\e[2 q"
    " 置換モード時に非点滅の下線タイプのカーソル
    let &t_SR .= "\e[4 q"
endif


"utf-8に設定
set fenc=utf-8

" 検索系
set ignorecase
set smartcase
set incsearch
set wrapscan
set hlsearch
nmap <Esc><Esc> :nohlsearch<CR><Esc>


" ctrl + a とかで行頭移動とか
inoremap <C-e> <Esc>$a
inoremap <C-a> <Esc>^a
noremap <C-e> <Esc>$a
noremap <C-a> <Esc>^a



"変換候補をポップアップで表示してくれるやつ
set completeopt=menuone
for k in split("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_",'\zs')
	exec "imap <expr> " . k . " pumvisible() ? '" . k . "' : '" . k . "\<C-X>\<C-P>\<C-N>'"
endfor


"paste をいい感じにする
if &term =~ "xterm"
	let &t_SI .= "\e[?2004h"
	let &t_EI .= "\e[?2004l"
	let &pastetoggle = "\e[201~"

	function XTermPasteBegin(ret)
		set paste
		return a:ret
	endfunction
	inoremap <special> <expr> <Esc>[200~ XTermPasteBegin("")
endif


"画面分割とtab関連 > https://qiita.com/tekkoc/items/98adcadfa4bdc8b5a6ca#タブページ関連
nnoremap s <Nop>
nnoremap sj <C-w>j
nnoremap sk <C-w>k
nnoremap sl <C-w>l
nnoremap sh <C-w>h
nnoremap sJ <C-w>J
nnoremap sK <C-w>K
nnoremap sL <C-w>L
nnoremap sH <C-w>H
nnoremap sn gt
nnoremap sp gT
nnoremap sr <C-w>r
nnoremap s= <C-w>=
nnoremap sw <C-w>w
nnoremap so <C-w>_<C-w>|
nnoremap sO <C-w>=
nnoremap sN :<C-u>bn<CR>
nnoremap sP :<C-u>bp<CR>
nnoremap st :<C-u>tabnew<CR>
nnoremap sT :<C-u>Unite tab<CR>
nnoremap ss :<C-u>sp<CR>
nnoremap sv :<C-u>vs<CR>
nnoremap sq :<C-u>q<CR>
nnoremap sQ :<C-u>bd<CR>
nnoremap sb :<C-u>Unite buffer_tab -buffer-name=file<CR>
nnoremap sB :<C-u>Unite buffer -buffer-name=file<CR>

"call submode#enter_with('bufmove', 'n', '', 's>', '<C-w>>')
"call submode#enter_with('bufmove', 'n', '', 's<', '<C-w><')
"call submode#enter_with('bufmove', 'n', '', 's+', '<C-w>+')
"call submode#enter_with('bufmove', 'n', '', 's-', '<C-w>-')
"call submode#map('bufmove', 'n', '', '>', '<C-w>>')
"call submode#map('bufmove', 'n', '', '<', '<C-w><')
"call submode#map('bufmove', 'n', '', '+', '<C-w>+')
"call submode#map('bufmove', 'n', '', '-', '<C-w>-')


"色つけれる時はつける
if has("syntax")
	syntax on
endif

"不可視文字を可視化するやつ
set list
set listchars=tab:--,eol:~,extends:>,precedes:<,trail:~

"保存時に行末の余分な空白を削除する
autocmd BufWritePre * :%s/\s\+$//ge

set visualbell


"------Status Line 関連------
"statuslineqを表示
set laststatus=2
"ファイル名表示
set statusline=%F
"変更チェック表示
set statusline+=%m
"読み込み専用フラグ
set statusline+=%r
"ヘルプバッファ
set statusline+=%h
"プレビューフラグ
set statusline+=%w
"これ以降は右寄せ表示
set statusline+=%=
"エンコーディングを表示
set statusline+=[ENC=%{&fileencoding}]
"現在行数/全体行数
set statusline+=[LOW=%l/%L]
"現在列数
set statusline+=[COLUMN=%c]


"vim -bで開くか*.binを開くと自動でバイナリモードに
augroup BinaryXXD
  autocmd!
  autocmd BufReadPre  *.bin let &binary =1
  autocmd BufReadPost * if &binary | silent %!xxd -g 1
  autocmd BufReadPost * set ft=xxd | endif
  autocmd BufWritePre * if &binary | %!xxd -r | endif
  autocmd BufWritePost * if &binary | silent %!xxd -g 1
  autocmd BufWritePost * set nomod | endif
augroup END

"挿入モード時にステータスバーの色変更
let g:hi_insert = 'highlight StatusLine guifg=cyan guibg=darkgray gui=none ctermfg=cyan ctermbg=darkgray cterm=none'

if has('syntax')
	augroup InsertHok
		autocmd!
		autocmd InsertEnter * call s:StatusLine('Enter')
		autocmd InsertLeave * call s:StatusLine('Leave')
	augroup END
endif

let s:slhlcmd = ''
function! s:StatusLine(mode)
	if a:mode == 'Enter'
		silent! let s:slhlcmd = 'highlight ' . s:GetHighlight('StatusLine')
		silent exec g:hi_insert
	else
		highlight clear StatusLine
		silent exec s:slhlcmd
	endif
endfunction

function! s:GetHighlight(hi)
	redir => hl
	exec 'highlight '.a:hi
	redir END
	let hl = substitute(hl, '[\r\n]', '', 'g')
	let hl = substitute(hl, 'xxx', '', '')
	return hl
endfunction



"全角スペースをハイライト
function! ZenkakuSpace()
	highlight ZenkakuSpace cterm=underline ctermfg=darkgrey gui=underline guifg=darkgrey
endfunction

if has('syntax')
	augroup ZenkakuSpace
		autocmd!
		"ZenkakuSpaceをカラーファイルで設定するなら次の行は削除
		autocmd ColorScheme       * call ZenkakuSpace()
		"全角スペースのハイライト指定
		autocmd VimEnter,WinEnter * match ZenkakuSpace /　/
		autocmd VimEnter,WinEnter * match ZenkakuSpace '\%u3000'
		augroup END
	call ZenkakuSpace()
endif




"拡張子がpyの時normal modeで (shift + m) を押すとpython filenameで実行
autocmd BufNewFile,BufRead *.py nnoremap <S-M> :!python %

"拡張子がtexの時normal modeで (shift + m) を押すとtexのコンパイルスクリプトを実行
autocmd BufNewFile,BufRead *.tex nnoremap <S-M> :!~/Dropbox/Apps/sh/tex.sh %


"Color Schemeをmolokaiに
colorscheme molokai
