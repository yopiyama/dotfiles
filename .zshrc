if [[ ! -n $TMUX ]]; then
  # get the IDs
  ID="`tmux list-sessions`"
  if [[ -z "$ID" ]]; then
    tmux new-session
  fi
  ID="`echo $ID | $PERCOL | cut -d: -f1`"
  tmux attach-session -t "$ID"
fi

export ZPLUG_HOME=/usr/local/opt/zplug
source $ZPLUG_HOME/init.zsh
zplug "zsh-users/zsh-autosuggestions"
zplug "zsh-users/zsh-completions"
zplug "zsh-users/zsh-syntax-highlighting"
zplug "zsh-users/zsh-history-substring-search"
zplug "chrissicool/zsh-256color"
zplug "peco/peco", as:command, from:gh-r
zplug "mollifier/anyframe"
if ! zplug check --verbose; then
  printf "Install? [y/N]: "
  if read -q; then
    echo; zplug install
  fi
fi
zplug load

export LANG=ja_JP.UTF-8
# 自動保管
autoload -U compinit; compinit
compinit -C
# コマンドミスを修正ss
setopt correct
# 大文字小文字区別しない
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'

# プロンプトの設定
autoload -U promptinit; promptinit
prompt pure
# PROMPT='[30;48;5;068m%F{white}%*[0m '$PROMPT

# viライクなキーバインディング
bindkey -v

zstyle ":anyframe:selector:" use peco
# C-eでcd履歴検索後移動
autoload -Uz chpwd_recent_dirs cdr add-zsh-hook
add-zsh-hook chpwd chpwd_recent_dirs
zstyle ':completion:*' recent-dirs-insert both
zstyle ':chpwd:*' recent-dirs-max 500
zstyle ':chpwd:*' recent-dirs-default true
zstyle ':chpwd:*' recent-dirs-file "$HOME/.zsh/.cache/chpwd-recent-dirs"
zstyle ':chpwd:*' recent-dirs-pushd true
bindkey '^E' anyframe-widget-cdr
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
HISTSIZE=1000
SAVEHIST=100000

alias mv='mv -i'
alias exa='exa --long'
alias ls='exa'
alias sl='ls'

if [ ~/.zshrc -nt ~/.zshrc.zwc ]; then
  zcompile ~/.zshrc
fi


