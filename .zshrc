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

# Zinit → https://qiita.com/taiyodayo/items/c1ebdc863e6baa18ea06
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
zinit light mollifier/anyframe
zinit light peco/peco

zinit ice pick"async.zsh" src"pure.zsh"
zinit light sindresorhus/pure

export LANG=ja_JP.UTF-8
# 自動保管
autoload -U compinit; compinit
# compinit -C
# コマンドミスを修正ss
setopt correct
# 大文字小文字区別しない
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'

# プロンプトの設定
# autoload -U promptinit; promptinit
# prompt pure

# viライクなキーバインディング
bindkey -v

# https://mollifier.hatenablog.com/entry/20081213/1229148947
# ctrl-a と ctrl-e の挙動だけ戻す
bindkey '^A' beginning-of-line
bindkey '^E' end-of-line

zstyle ":anyframe:selector:" use peco
# C-hでcd履歴検索後移動
autoload -Uz chpwd_recent_dirs cdr add-zsh-hook
add-zsh-hook chpwd chpwd_recent_dirs
zstyle ':completion:*' recent-dirs-insert both
zstyle ':chpwd:*' recent-dirs-max 500
zstyle ':chpwd:*' recent-dirs-default true
zstyle ':chpwd:*' recent-dirs-file "$HOME/.zsh/.cache/chpwd-recent-dirs"
zstyle ':chpwd:*' recent-dirs-pushd true
bindkey '^H' anyframe-widget-cdr
# C-rでコマンド履歴検索後実行
bindkey '^R' anyframe-widget-execute-history
# C-fでファイル名検索，挿入
bindkey '^F' anyframe-widget-insert-filename
# cd した先のディレクトリをディレクトリスタックに追加する
# ディレクトリスタックとは今までに行ったディレクトリの履歴のこと
# `cd +<Tab>` でディレクトリの履歴が表示され、そこに移動できる
setopt auto_pushd
DIRSTACKSIZE=100
# pushd したとき、ディレクトリがすでにスタックに含まれていればスタックに追加しない
setopt pushd_ignore_dups

alias dirs='dirs -v'
# History
# 入力したコマンドがすでにコマンド履歴に含まれる場合、履歴から古いほうのコマンドを削除する
# コマンド履歴とは今まで入力したコマンドの一覧のことで、上下キーでたどれる
HISTFILE=${HOME}/.zsh/.zhistory
setopt hist_ignore_all_dups
setopt share_history
setopt hist_no_store
setopt extended_history
HISTSIZE=1000
SAVEHIST=100000
alias history='history -i'

alias mv='mv -i'
alias exa='exa --long --icons -F --group-directories-first --time-style=long-iso'
alias ls='exa'

# https://qiita.com/k725/items/5c220a4ab87eb84a8233
# tmux も併用している場合は一工夫必要 https://zenn.dev/kyoshida/articles/1cf9099e865ce8
function ssh_color() {
    case $1 in
        # Prefix が prod-c- →紫
        prod-c-* ) echo -e "\033Ptmux;\033\033]1337;SetProfile=ssh-purple\007\033\\";;
        # Prefix が prod- → 赤
        prod-* ) echo -e "\033Ptmux;\033\033]1337;SetProfile=ssh-red\007\033\\";;
        # Prefix が dev →青
        dev* ) echo -e "\033Ptmux;\033\033]1337;SetProfile=ssh-blue\007\033\\";;
        *) echo -e "\033Ptmux;\033\033]1337;SetProfile=Main\007\033\\";;
    esac
    /usr/bin/ssh $@
    echo -e "\033Ptmux;\033\033]50;SetProfile=Main\007\033\\"
}

alias ssh='ssh_color'
compdef _ssh ssh_color=ssh

if [[ -x `which colordiff` ]]; then
  alias diff='colordiff'
fi


if [ ~/.zshrc -nt ~/.zshrc.zwc ]; then
  zcompile ~/.zshrc
fi

case ${OSTYPE} in
    darwin*)
        alias xargs='gxargs'
		alias sed='gsed'
		alias awk='gawk'
        ;;

esac
