#!/usr/bin/env bash
# PostToolUse hook (matcher: TaskCreate|TaskUpdate): Claude Code のタスク
# リストを Obsidian のノートにミラーする「対応状況管理」フック。
#
# タスク状態は ~/.claude/tasks/<session_id>/<id>.json に 1 タスク 1 ファイル
# で永続化される（フィールド: id / subject / description / activeForm /
# status / blocks / blockedBy）。フックはツール入力を解釈せず、毎回この
# ディレクトリ全体を読み直してノートを全量書き換える。差分追跡が不要になり、
# タスク削除（JSON ファイルの消滅）も自動で反映される。
#
# ノートは ClaudeCode/<project>/Tasks/<YYYYMM>/ 配下に
# <stamp>_<branch>_<slug>.md (session_note_basename の出力) として置き、
# 冒頭でセッションログノート
# (ClaudeCode/<project>/Conversations/<YYYYMM>/ 配下) へ wikilink する。
# タスクノートとセッションログノートは basename が同一（suffix なし）で
# 衝突するため、リンクは basename ではなく vault ルートからのフルパスで
# 修飾する（[[パス|表示名]]）。命名は obsidian-note-lib.sh に一元化されて
# おり、パス一致でリンクが成立する。
#
# サブエージェントがタスクを操作した場合も session_id（= タスクディレクトリ）
# は親と共通なので、transcript_path が subagents/ 配下なら親 transcript に
# 読み替えて、常に親セッションのタスクノート 1 枚に集約する。
#
# 書き込みが obsidian CLI ではなく vault への直接ファイル書き込みなのは
# log-to-obsidian.sh と同じ理由（CLI は Electron cold boot + single-instance
# lock の奪い合いがある）。並行フック起動に備え、temp file + mv で
# アトミックに置き換える。
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/obsidian-note-lib.sh"

input="$(cat)"
session_id="$(jq -r '.session_id // empty' <<<"$input")"
transcript_path="$(jq -r '.transcript_path // empty' <<<"$input")"
cwd="$(jq -r '.cwd // empty' <<<"$input")"

[[ -n "$session_id" ]] || exit 0

tasks_dir="$HOME/.claude/tasks/$session_id"
[[ -d "$tasks_dir" ]] || exit 0

# タスク JSON を id 数値順に連結して Markdown チェックリストへ変換する。
# - completed   → - [x]
# - in_progress → - [/] + 太字（Obsidian で「作業中」が一目で分かるように）
# - pending     → - [ ]
# description はネストした引用行、blockedBy は末尾の注記として付ける。
# status=deleted のファイルが残っていても表示しない（通常は削除される）。
shopt -s nullglob
task_files=("$tasks_dir"/*.json)
shopt -u nullglob
(( ${#task_files[@]} > 0 )) || exit 0

checklist="$(jq -rs '
  map(select(.status != "deleted"))
  | sort_by(.id | tonumber? // 0) as $tasks
  | ([$tasks[] | select(.status == "completed")] | length) as $done
  | "進捗: \($done)/\($tasks | length) 完了\n\n"
    + ($tasks
       | map(
           (if .status == "completed" then "- [x] "
            elif .status == "in_progress" then "- [/] "
            else "- [ ] " end)
           + "#\(.id) "
           + (if .status == "in_progress" then "**\(.subject)**" else .subject end)
           + (if (.blockedBy // []) | length > 0
              then "（⏳ " + ((.blockedBy) | map("#\(.)") | join(", ")) + " 待ち）"
              else "" end)
           + ((.description // "")
              | if length > 0
                then split("\n") | map("\n    > \(.)") | join("")
                else "" end)
         )
       | join("\n"))
' "${task_files[@]}")"
[[ -n "$checklist" ]] || exit 0

# サブエージェント経由の呼び出しでも親セッションのノートに集約する。
session_transcript="$transcript_path"
if [[ "$transcript_path" == */subagents/* ]]; then
  session_transcript="${transcript_path%/subagents/*}.jsonl"
fi
[[ -f "$session_transcript" ]] || exit 0

project="$(resolve_project "$session_transcript" "$cwd")"
started_at="$(jq -rn 'first(inputs | .timestamp // empty)' "$session_transcript")"
stamp="$(note_stamp "$started_at")"
[[ -n "$stamp" ]] || exit 0

vault_root="$(resolve_vault_root)"
[[ -n "$vault_root" && -d "$vault_root" ]] || exit 0

state_dir="$(obsidian_state_dir)"
session_note="$(session_note_basename "$session_transcript" false "$session_id" "$state_dir" "$stamp")"
[[ -n "$session_note" ]] || exit 0
yyyymm="$(note_yyyymm "$stamp")"
conv_note="ClaudeCode/${project}/Conversations/${yyyymm}/${session_note}"
note_file="$vault_root/ClaudeCode/${project}/Tasks/${yyyymm}/${session_note}.md"
mkdir -p "$(dirname "$note_file")"

tmp_file="$(mktemp "${note_file}.XXXXXX")"
{
  printf -- '---\nsession_id: %s\nproject: %s\nupdated_at: %s\n---\n\n' \
    "$session_id" "$project" "$(date +%Y-%m-%dT%H:%M:%S)"
  printf -- 'セッションログ: [[%s|%s]]\n\n%s\n' "$conv_note" "$session_note" "$checklist"
} > "$tmp_file"
mv "$tmp_file" "$note_file"
