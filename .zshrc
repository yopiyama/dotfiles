export LANG=ja_JP.UTF-8

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

# 入力したコマンドがすでにコマンド履歴に含まれる場合、履歴から古いほうのコマンドを削除する
# コマンド履歴とは今まで入力したコマンドの一覧のことで、上下キーでたどれる
setopt hist_ignore_all_dups

#HISTSIZE=50
#SAVEHIST=50

# pyenvの設定
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

alias ls='ls -ilGF'

source "${ZDOTDIR:-$HOME}/.zprezto/init.zsh"
