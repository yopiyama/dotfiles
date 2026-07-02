# log-to-obsidian.sh / sync-tasks-to-obsidian.sh 共通の
# ノート命名・保存先解決ヘルパー。bash から source して使う（直接実行しない）。
#
# タスクノート→セッションログノートの wikilink はノート名の完全一致で
# 成立するため、命名ロジックは必ずここに一元化し、各スクリプトへ
# コピーしないこと（片方だけ変えるとリンクが黙って切れる）。

# ISO timestamp をファイル名用 (先頭19文字・コロンを - に置換) に整形する。
note_stamp() {
  local ts="${1:0:19}"
  printf '%s' "${ts//:/-}"
}

# 最初のユーザー発言(サブエージェントならタスク文)の全文を返す。
# first_user_message <transcript_path> <is_subagent:true|false>
first_user_message() {
  jq -rn --argjson is_subagent "$2" '
    first(
      inputs
      | select(.type == "user")
      | select($is_subagent or (.isSidechain != true))
      | select(.isMeta != true)
      | .message.content
      | if type == "string" then .
        else ([.[] | select(.type == "text") | .text] | join(" "))
        end
      | gsub("\\s+"; " ")
      | sub("^ +"; "") | sub(" +$"; "")
      | select(length > 0)
    )
  ' "$1"
}

# Claude による要約が使えない/失敗した場合のフォールバック slug。
# 先頭30文字にそのまま切り詰めるだけの単純な要約。
# fallback_slug <text>
fallback_slug() {
  local text="${1//\//_}"
  if (( ${#text} > 30 )); then
    printf '%s…' "${text:0:30}"
  else
    printf '%s' "$text"
  fi
}

# 最初のユーザー発言を Claude (haiku, hooks 無効・非永続) で25文字以内の
# 見出しに要約する。この呼び出し自体が Stop フックを再発火して自分自身を
# ログしてしまわないよう --safe-mode (hooks/CLAUDE.md/MCP 等を無効化、
# 認証は通常の OAuth のまま) と --no-session-persistence (transcript を
# 一切書き出さない) を必ず付ける。失敗・空応答時は fallback_slug を使う。
# summarize_slug <transcript_path> <is_subagent:true|false>
summarize_slug() {
  local text summarized
  text="$(first_user_message "$1" "$2")"
  [[ -z "$text" ]] && { printf '無題'; return; }

  # claude -p が非ゼロ終了 (ネットワーク不調・予算超過等) しても
  # set -e で呼び出し元スクリプトごと落ちないよう `|| true` で握り潰す。
  summarized="$(claude -p --safe-mode --no-session-persistence \
    --model haiku --output-format text --max-budget-usd 0.02 \
    "次のユーザーの発言を25文字以内の日本語の見出しに要約して。見出しのみを1行で出力し、記号・句読点・前置きは付けないこと:

${text}" 2>/dev/null | tr -d '\n')" || true
  summarized="${summarized//\//_}"

  if [[ -n "$summarized" ]]; then
    printf '%s' "$summarized"
  else
    printf '%s' "$(fallback_slug "$text")"
  fi
}

# 作業ブランチの短縮名。パスの最後のセグメントだけを使い、長すぎる
# ブランチ名でファイル名が肥大化しないよう上限を設ける。
# ブランチが取れない(非 git dir / detached 等)場合は空文字を返す。
# note_branch <transcript_path>
note_branch() {
  local branch
  branch="$(jq -rn 'first(inputs | .gitBranch // empty)' "$1")"
  [[ -z "$branch" ]] && return
  branch="${branch##*/}"
  if (( ${#branch} > 24 )); then
    branch="${branch:0:24}"
  fi
  printf '%s' "$branch"
}

# セッション/サブエージェントノートの basename ("{stamp}_{branch}_{slug}",
# ブランチが取れない場合は "{stamp}_{slug}") を解決する。
# slug の要約は state_dir に cache_key ごとキャッシュし、同一セッション内で
# 何度呼ばれても Claude 呼び出しが1回で済むようにする（タスクノートと
# 会話ログノートの両方から呼ばれるため、basename を一致させる意味もある）。
# session_note_basename <transcript_path> <is_subagent> <cache_key> <state_dir> <stamp>
session_note_basename() {
  local transcript="$1" is_subagent="$2" cache_key="$3" state_dir="$4" stamp="$5"
  local cache_file="${state_dir}/${cache_key}.slug" slug branch

  if [[ -s "$cache_file" ]]; then
    slug="$(cat "$cache_file")"
  else
    slug="$(summarize_slug "$transcript" "$is_subagent")"
    printf '%s' "$slug" > "$cache_file"
  fi

  branch="$(note_branch "$transcript")"
  if [[ -n "$branch" ]]; then
    printf '%s_%s_%s' "$stamp" "$branch" "$slug"
  else
    printf '%s_%s' "$stamp" "$slug"
  fi
}

# ノートを月別フォルダに分けるための YYYYMM を stamp (または ISO timestamp)
# から取り出す。イベント時刻ではなくセッション開始時刻由来の stamp を渡す
# こと。月をまたぐセッションでもノートが複数フォルダに分裂しないようにする。
# note_yyyymm <stamp>
note_yyyymm() {
  printf '%s%s' "${1:0:4}" "${1:5:2}"
}

# ノートの保存先フォルダはイベント時点の cwd ではなくセッション開始時の
# cwd から決める。ターン途中で cd すると同一セッションのノートが別フォルダに
# 分裂するため。さらに git リポジトリ内ならリポジトリルート名を使い、
# サブディレクトリから起動したセッションも同じフォルダにまとめる。
# resolve_project <transcript_path> <fallback_cwd>
resolve_project() {
  local session_cwd git_root
  session_cwd="$(jq -rn 'first(inputs | .cwd // empty)' "$1")"
  [[ -z "$session_cwd" ]] && session_cwd="$2"
  git_root="$(git -C "$session_cwd" rev-parse --show-toplevel 2>/dev/null || true)"
  basename "${git_root:-$session_cwd}"
}

# 冪等性・キャッシュ用のマシンローカル state ディレクトリを返す
# (このリポジトリの管理対象外＝git管理されないマシンローカル状態)。
# log-to-obsidian.sh の行番号カウンタ (*.count) と
# session_note_basename の要約キャッシュ (*.slug) を両方ここに置く。
obsidian_state_dir() {
  local dir="$HOME/.claude/claude-obsidian-log"
  mkdir -p "$dir"
  printf '%s' "$dir"
}

# vault のルートを Obsidian の vault レジストリから解決する。
# basename が obsidian の vault を優先し、見つからなければ先頭の vault に
# フォールバックする。レジストリが無ければ空文字を返す（呼び出し側で判定）。
resolve_vault_root() {
  local vault_registry="$HOME/Library/Application Support/obsidian/obsidian.json"
  [[ -f "$vault_registry" ]] || return 0
  jq -r '
    [.vaults[].path]
    | (map(select(split("/") | last == "obsidian")) + .)
    | .[0] // empty
  ' "$vault_registry"
}
