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

# ノートファイル名は最初のユーザー発言(サブエージェントならタスク文)の
# 先頭を要約として使う。Session ID っぽい無意味な suffix を避けるため。
# note_slug <transcript_path> <is_subagent:true|false>
note_slug() {
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
      | gsub("/"; "_")
      | sub("^ +"; "") | sub(" +$"; "")
      | select(length > 0)
      | if length > 30 then .[0:30] + "…" else . end
    )
  ' "$1"
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
