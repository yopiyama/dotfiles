# Amazon Q pre block. Keep at the top of this file.
[[ -f "${HOME}/Library/Application Support/amazon-q/shell/zshrc.pre.zsh" ]] && builtin source "${HOME}/Library/Application Support/amazon-q/shell/zshrc.pre.zsh"
# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

export TMUX_TMPDIR=$HOME/.tmux/tmp
# no server running on /private/tmp/tmux-503/default
# [exited]
# no sessions
# tmux new → exited となる場合
# brew install reattach-to-user-namespace

if [[ ! -n $TMUX ]]; then
  # get the IDs
  ID="`tmux list-sessions`"
  if [[ -z "$ID" ]]; then
    tmux new-session
  fi
  ID="`echo $ID | $PERCOL | cut -d: -f1`"
  tmux attach-session -t "$ID"
fi

#----------------------------------- zinit config -----------------------------------
### Added by Zinit's installer
if [[ ! -f $HOME/.zinit/bin/zinit.zsh ]]; then
    print -P "%F{33}▓▒░ %F{220}Installing %F{33}DHARMA%F{220} Initiative Plugin Manager (%F{33}zdharma-continuum/zinit%F{220})…%f"
    command mkdir -p "$HOME/.zinit" && command chmod g-rwX "$HOME/.zinit"
    command git clone https://github.com/zdharma-continuum/zinit "$HOME/.zinit/bin" && \
        print -P "%F{33}▓▒░ %F{34}Installation successful.%f%b" || \
        print -P "%F{160}▓▒░ The clone has failed.%f%b"
fi

source "$HOME/.zinit/bin/zinit.zsh"
autoload -Uz _zinit
(( ${+_comps} )) && _comps[zinit]=_zinit
### End of Zinit's installer chunk

zinit light zsh-users/zsh-autosuggestions
zinit light zsh-users/zsh-completions
zinit light zsh-users/zsh-syntax-highlighting
zinit light zsh-users/zsh-history-substring-search
zinit light chrissicool/zsh-256color
zinit light romkatv/powerlevel10k

#----------------------------------- General config -----------------------------------

export LANG=ja_JP.UTF-8
# 自動保管
autoload -U compinit; compinit
# コマンドミスを修正
setopt correct
# 大文字小文字区別しない
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'

autoload -Uz chpwd_recent_dirs cdr add-zsh-hook
add-zsh-hook chpwd chpwd_recent_dirs
zstyle ':completion:*' recent-dirs-insert both
zstyle ':chpwd:*' recent-dirs-max 500
zstyle ':chpwd:*' recent-dirs-default true
zstyle ':chpwd:*' recent-dirs-file "$HOME/.zsh/.cache/chpwd-recent-dirs"
zstyle ':chpwd:*' recent-dirs-pushd true

# cd した先のディレクトリをディレクトリスタックに追加する
# ディレクトリスタックとは今までに行ったディレクトリの履歴のこと
# `cd +<Tab>` でディレクトリの履歴が表示され、そこに移動できる
setopt auto_pushd
DIRSTACKSIZE=100
# pushd したとき、ディレクトリがすでにスタックに含まれていればスタックに追加しない
setopt pushd_ignore_dups

# History
# 入力したコマンドがすでにコマンド履歴に含まれる場合、履歴から古いほうのコマンドを削除する
# コマンド履歴とは今まで入力したコマンドの一覧のことで、上下キーでたどれる
HISTFILE=${HOME}/.zsh/.zhistory
setopt hist_ignore_all_dups
setopt share_history
setopt hist_no_store
setopt extended_history
HISTSIZE=10000
SAVEHIST=100000
HISTTIMEFORMAT='%Y/%m/%d %H:%M:%S '

export PATH="$HOME/.rd/bin:$PATH"

# Prompt を画面下へ固定
tput cup $LINES
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

export FZF_DEFAULT_COMMAND="rg --hidden --follow --glob '!**/.git/'"
export FZF_DEFAULT_OPTS='--height 50%  --border --inline-info'

# ----------------------------------- Functions -----------------------------------
function fzf-cdr() {
  target_dir=`cdr -l | sed 's/^[^ ][^ ]*  *//' | fzf  --preview="eza --long --icons --git -F --group-directories-first --time-style=long-iso -I '**/.git/' '{-1}'" --preview-window=down`
  target_dir=`echo ${target_dir/\~/$HOME}`
  if [ -n "$target_dir" ]; then
    BUFFER="cd ${target_dir}"
    tput cup $LINES
    CURSOR=${#BUFFER}
    # zle reset-prompt
    zle .redisplay
  fi
}
zle -N fzf-cdr

function fzf-file-list() {
  BUFFER="${BUFFER}"`eval $FZF_DEFAULT_COMMAND | fzf  --preview="bat '{-1}' --color=always" --preview-window=down`
  tput cup $LINES
  CURSOR=${#BUFFER}
  zle .redisplay
  # zle reset-prompt
}
zle -N fzf-file-list

function fzf-history() {
  # BUFFER=$(history -n -r 1 | cut -d ' ' -f 4- | fzf --query "$LBUFFER" --reverse)
  BUFFER=$(history -n -r 1 | fzf --query "$LBUFFER" --reverse | cut -d ' ' -f 4-)
  tput cup $LINES
  CURSOR=${#BUFFER}
  zle .redisplay
}
zle -N fzf-history

# ctrl-l で画面を再描画した時の設定
function myclear() {
  if [[ -n "$__MYCLEAR_RUNNING" ]]; then return; fi
  __MYCLEAR_RUNNING=1

  clear
  tput cup $LINES
  zle .reset-prompt
  unset __MYCLEAR_RUNNING
}
zle -N myclear

# ----------------------------------- Key Binding -----------------------------------
# viライクなキーバインディング
bindkey -v
# https://mollifier.hatenablog.com/entry/20081213/1229148947
# ctrl-a と ctrl-e, ctrl-k の挙動だけ戻す
bindkey '^A' beginning-of-line
bindkey '^E' end-of-line
bindkey '^K' kill-line
# C-hでcd履歴検索後移動
# bindkey '^H' anyframe-widget-cdr
bindkey '^H' fzf-cdr
# C-rでコマンド履歴検索後実行
bindkey '^R' fzf-history
# C-fでファイル名検索，挿入
bindkey '^F' fzf-file-list
# C-l 時の挙動
bindkey '^L' myclear

#----------------------------------- Alias -----------------------------------
alias dirs='dirs -v'
alias history='history -i'
alias hist='fc'
alias mv='mv -i'
alias rm='rm -i'
alias ll='eza --long --icons --git -F --group-directories-first --time-style=long-iso -I "**/.git/"'
alias bat='bat --color=always'
alias tf='terraform'
alias tf-p='terraform plan | tee >(grep -E "# \w|Plan:" > /tmp/_plan_abst.log) && cat /tmp/_plan_abst.log'

# clear で画面を再描画した時の設定
alias clear="clear;tput cup $LINES"

# 個別の Alias 設定

if [[ -x `which colordiff` ]]; then
  alias diff='colordiff'
fi

case ${OSTYPE} in
    darwin*)
      alias xargs='gxargs'
      alias sed='gsed'
      alias awk='gawk'
      alias cpjson='pbpaste | jq | pbcopy'
      ;;
esac

#----------------------------------- Compile zshrc at end -----------------------------------
if [ ~/.zshrc -nt ~/.zshrc.zwc ]; then
  zcompile ~/.zshrc
fi
