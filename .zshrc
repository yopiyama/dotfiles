export ZPLUG_HOME=/usr/local/opt/zplug
source $ZPLUG_HOME/init.zsh

export LANG=ja_JP.UTF-8

autoload -U promptinit; promptinit
prompt pure

# 自動保管
autoload -U compinit; compinit

# コマンドミスを修正
setopt correct

# cdコマンドを省略して、ディレクトリ名のみの入力で移動
setopt auto_cd

# viライクなキーバインディング
bindkey -v

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

alias ls='ls -ilGF'

# export PYENV_ROOT="${HOME}/.pyenv"
# export PATH=${PYENV_ROOT}/bin:$PATH
eval "$(pyenv init -)"


# Plugin - zplug
zplug "zsh-users/zsh-autosuggestions"
zplug "zsh-users/zsh-completions"
zplug "zsh-users/zsh-syntax-highlighting"
zplug "zsh-users/zsh-history-substring-search"
zplug "chrissicool/zsh-256color"

if ! zplug check --verbose; then
  printf "Install? [y/N]: "
  if read -q; then
    echo; zplug install
  fi
fi

zplug load

if [ ~/.zshrc -nt ~/.zshrc.zwc ]; then
  zcompile ~/.zshrc
fi

