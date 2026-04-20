# Kiro CLI pre block. Keep at the top of this file.
if [[ "${TERM_PROGRAM:-}" == "kiro" ]]; then
  [[ -f "${HOME}/Library/Application Support/kiro-cli/shell/zshrc.pre.zsh" ]] && builtin source "${HOME}/Library/Application Support/kiro-cli/shell/zshrc.pre.zsh"
fi

# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

export TMUX_TMPDIR=$HOME/.tmux/tmp

# iTerm で起動したときだけ tmux を自動起動する（VSCode/Kiro 等の統合ターミナルでは起動しない）
_is_iterm() {
  [[ -n "${ITERM_SESSION_ID:-}" || "${TERM_PROGRAM:-}" == "iTerm.app" ]]
}
_is_vscode() {
  [[ "${TERM_PROGRAM:-}" == "vscode" || -n "${VSCODE_IPC_HOOK_CLI:-}" ]]
}
_is_kiro() {
  [[ "${TERM_PROGRAM:-}" == "kiro" ]]
}

if [[ -z ${TMUX:-} ]] && _is_iterm && ! _is_kiro; then
  rel="${PWD#$HOME}"
  [[ -z "$rel" ]] && rel="/"
  sessions="$(tmux list-sessions -F '#S' 2>/dev/null)"
  if [[ -z "$sessions" ]]; then
    tmux new-session -s "iTerm/$rel"
  elif [[ $(echo "$sessions" | wc -l) -eq 1 ]]; then
    tmux attach-session -t "$sessions"
  else
    ID="$(printf '+ new (iTerm/%s)\n%s\n' "$rel" "$sessions" | fzf --prompt='tmux> ' --height=40% --reverse --no-sort)"
    if [[ "$ID" == "+ new "* ]]; then
      tmux new-session -A -s "iTerm/$rel"
    elif [[ -n "$ID" ]]; then
      tmux attach-session -t "$ID"
    fi
  fi
  unset rel sessions ID
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

# プロンプト本体は即時ロード (instant prompt の整合性のため)
zinit light romkatv/powerlevel10k

# 重いプラグインはプロンプト表示後に遅延ロード (turbo mode)
zinit wait lucid light-mode for \
    zsh-users/zsh-syntax-highlighting \
  atload"!_zsh_autosuggest_start" \
    zsh-users/zsh-autosuggestions \
  blockf \
    zsh-users/zsh-completions \
    zsh-users/zsh-history-substring-search

#----------------------------------- General config -----------------------------------

export LANG=ja_JP.UTF-8
# 自動保管 (dump は 24h 以上経過時のみ security check する)
autoload -Uz compinit
() {
  emulate -L zsh
  local stale=(${ZDOTDIR:-$HOME}/.zcompdump(Nmh+24))
  if (( ${#stale} )); then
    compinit
  else
    compinit -C
  fi
}
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
function __fzf_select_dir() {
  emulate -L zsh
  local query="$1"

  # クエリにパス区切りが含まれる場合、ディレクトリ部分を検索ルートにする
  local search_root="."
  local fzf_query="$query"
  if [[ "$query" == */* ]]; then
    local dir_part="${query%/*}"
    if [[ -d "$dir_part" ]]; then
      search_root="$dir_part"
      fzf_query="${query##*/}"
    fi
  fi

  local selected
  selected="$(
    {
      if (( $+commands[fd] )); then
        # 浅いパスを先に流してから深いパスを流す
        fd --type d --hidden --follow --exclude .git --max-depth 1 . "$search_root" 2>/dev/null
        fd --type d --hidden --follow --exclude .git --min-depth 2 --max-depth 5 . "$search_root" 2>/dev/null
      else
        find "$search_root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null
        find "$search_root" -mindepth 2 -maxdepth 5 -type d \
          -not -path '*/Library/*' -not -path '*/.git/*' 2>/dev/null
      fi
    } | sed 's|^\./||' \
      | fzf --query "$fzf_query" --scheme=path --tiebreak=begin,length \
            --preview="eza --long --icons --git -F --group-directories-first --time-style=long-iso -I '**/.git/' '{-1}'" \
            --preview-window=down
  )"
  print -r -- "$selected"
}

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

function smart-cd-tab() {
  emulate -L zsh
  local buffer="$LBUFFER"
  local -a match

  if [[ $buffer =~ '(^|[[:space:]])cd[[:space:]]+([^;&|]*)$' ]]; then
    local query="${match[2]}"
    if [[ -z "$query" || "$query" == -* || "$query" == ~* || "$query" == /* ]]; then
      zle expand-or-complete
      return
    fi

    local selected
    selected="$(__fzf_select_dir "$query")"
    if [[ -n "$selected" ]]; then
      local base_len=$(( ${#buffer} - ${#query} ))
      local base="${buffer:0:$base_len}"
      LBUFFER="${base}${(q-)selected}"
    fi
    zle reset-prompt
    return
  fi

  zle expand-or-complete
}
zle -N smart-cd-tab

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
# Tab は cd のときだけ fzf、通常は補完
bindkey -M viins '^I' smart-cd-tab
bindkey -M emacs '^I' smart-cd-tab

#----------------------------------- Alias -----------------------------------
alias dirs='dirs -v'
alias history='history -i'
alias hist='fc'
alias mv='mv -i'
alias rm='rm -i'
alias ls='eza --icons'
alias ll='eza --long --icons --git -F --group-directories-first --time-style=long-iso -I "**/.git/"'
alias bat='bat --color=always --show-all'
alias tf='terraform'
alias tf-p='terraform plan | tee >(grep -E "# \w|Plan:" > /tmp/_plan_abst.log) && cat /tmp/_plan_abst.log'
alias ruff='uvx ruff'
# nvim を引数無しで起動したらカレントディレクトリを開く
nvim() {
  if (( $# == 0 )); then
    command nvim .
  else
    command nvim "$@"
  fi
}
alias nv='nvim'

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

new-worktree() {
  local branch=$1
  local repo=$(basename $(git rev-parse --show-toplevel))
  local dir="${2:-../${repo}.worktrees/${branch//\//-}}"

  # 既存ブランチかどうかで分岐
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    git worktree add "$dir" "$branch"
  else
    git worktree add "$dir" -b "$branch"
  fi

  cd "$dir"
  if [[ -f "mise.toml" ]] || [[ -f ".mise.toml" ]]; then
      mise trust
  fi
  claude mcp add serena -- uvx --from git+https://github.com/oraios/serena \
    serena start-mcp-server --context claude-code --project "$(pwd)"
  echo "✅ Worktree + Serena ready at $(pwd)"
}

#----------------------------------- Compile zshrc at end -----------------------------------
if [ ~/.zshrc -nt ~/.zshrc.zwc ]; then
  zcompile ~/.zshrc
fi

# Kiro CLI post block. Keep at the bottom of this file.
if [[ "${TERM_PROGRAM:-}" == "kiro" ]]; then
  [[ -f "${HOME}/Library/Application Support/kiro-cli/shell/zshrc.post.zsh" ]] && builtin source "${HOME}/Library/Application Support/kiro-cli/shell/zshrc.post.zsh"
fi

[[ "$TERM_PROGRAM" == "kiro" ]] && . "$(kiro --locate-shell-integration-path zsh)"
eval "$( /opt/homebrew/bin/mise activate zsh)"
