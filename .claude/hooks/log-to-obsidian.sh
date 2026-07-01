#!/usr/bin/env bash
# Stop / SubagentStop hook: 会話ターンが完了するたびに、直前のフック実行
# 以降に増えたトランスクリプト行を Obsidian のノートに追記する。
#
# サブエージェント（Task ツール）は session_id が親と同一のまま、別の
# transcript_path（isSidechain: true の行のみ）で完了報告してくる。
# session_id だけをキーにすると親と同じ state ファイル・同じノートを
# 取り合って行番号ブックキーピングが壊れる（=会話が混ざる）ため、
# SubagentStop のときは agent_id を使って親とは別の state/ノートに分ける。
#
# 冪等性は $HOME/.claude/claude-obsidian-log/<key>.count に
# 「これまでに読み込んだトランスクリプト行数」を保存することで担保する
# （このリポジトリの管理対象外＝git管理されないマシンローカル状態）。
set -euo pipefail

input="$(cat)"
session_id="$(jq -r '.session_id // empty' <<<"$input")"
transcript_path="$(jq -r '.transcript_path // empty' <<<"$input")"
cwd="$(jq -r '.cwd // empty' <<<"$input")"
hook_event_name="$(jq -r '.hook_event_name // empty' <<<"$input")"
agent_id="$(jq -r '.agent_id // empty' <<<"$input")"
agent_type="$(jq -r '.agent_type // empty' <<<"$input")"

[[ -n "$session_id" && -n "$transcript_path" && -f "$transcript_path" ]] || exit 0

is_subagent=false
[[ "$hook_event_name" == "SubagentStop" && -n "$agent_id" ]] && is_subagent=true

state_dir="$HOME/.claude/claude-obsidian-log"
mkdir -p "$state_dir"
if [[ "$is_subagent" == "true" ]]; then
  state_file="$state_dir/${session_id}_${agent_id}.count"
else
  state_file="$state_dir/${session_id}.count"
fi

# Stop フック起動時点では、直前のツール呼び出し後に続く
# アシスタントの最終テキストがまだ transcript ファイルに
# 書き込まれていないことがある（書き込みとフック起動のレース）。
# 末尾の user/assistant エントリが「tool_use を含まない text 付き
# assistant」になる（＝ターンが本当に完了した）まで少し待つ。
turn_is_complete() {
  tail -n 50 "$transcript_path" | jq -s '
    [.[] | select(.type == "assistant" or .type == "user")] as $convo
    | if ($convo | length) == 0 then false
      else
        $convo[-1] as $last
        | ($last.type == "assistant")
          and (($last.message.content // []) | any(.type == "text"))
          and (($last.message.content // []) | any(.type == "tool_use") | not)
      end
  ' 2>/dev/null
}

attempts=0
while [[ "$(turn_is_complete)" != "true" ]] && (( attempts < 15 )); do
  sleep 0.2
  attempts=$((attempts + 1))
done

total_lines="$(wc -l < "$transcript_path" | tr -d ' ')"
last_synced=0
[[ -f "$state_file" ]] && last_synced="$(cat "$state_file")"

if (( total_lines <= last_synced )); then
  exit 0
fi

chunk="$(sed -n "$((last_synced + 1)),${total_lines}p" "$transcript_path" | jq -rs --argjson is_subagent "$is_subagent" '
  def summarize_input:
    if has("command") then .command
    elif has("file_path") then .file_path
    elif has("pattern") then .pattern
    elif has("query") then .query
    elif has("url") then .url
    else tostring end
    | if length > 150 then .[0:150] + "…" else . end;

  .[]
  | select(.type == "user" or .type == "assistant")
  | select($is_subagent or (.isSidechain != true))
  | select(.isMeta != true)
  | . as $line
  | ($line.timestamp // "" | if length >= 16 then .[11:16] else "" end) as $hhmm
  | if $line.type == "user" then
      ($line.message.content
        | if type == "string" then .
          else ([.[] | select(.type == "text") | .text] | join("\n"))
          end) as $text
      | if ($text | length) > 0 then
          "### \($hhmm) User\n\($text)\n"
        else empty end
    else
      ([$line.message.content[] | select(.type == "text") | .text] | join("\n")) as $text
      | ([$line.message.content[] | select(.type == "tool_use") | "🔧 \(.name): \(.input | summarize_input)"] | join("\n")) as $tools
      | if ($text | length) > 0 or ($tools | length) > 0 then
          "### \($hhmm) Assistant\n"
          + (if ($text | length) > 0 then "\($text)\n" else "" end)
          + (if ($tools | length) > 0 then "\($tools)\n" else "" end)
        else empty end
    end
')"

if [[ -z "$chunk" ]]; then
  echo "$total_lines" > "$state_file"
  exit 0
fi

project="$(basename "$cwd")"
started_at="$(jq -r 'select(.timestamp != null) | .timestamp' "$transcript_path" | head -1)"
timestamp="${started_at:0:19}"
timestamp="${timestamp//:/-}"
[[ -z "$timestamp" ]] && timestamp="$(date +%Y-%m-%dT%H-%M-%S)"

# ノートファイル名は最初のユーザー発言(サブエージェントならタスク文)の
# 先頭を要約として使う。Session ID っぽい無意味な suffix を避けるため。
slug="$(jq -r --argjson is_subagent "$is_subagent" '
  select(.type == "user")
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
' "$transcript_path" | head -1)"
[[ -z "$slug" ]] && slug="無題"

if [[ "$is_subagent" == "true" ]]; then
  agent_short="${agent_id:0:8}"
  note_path="ClaudeCode/${project}/${timestamp}_${slug}_${agent_short}.md"
else
  note_path="ClaudeCode/${project}/${timestamp}_${slug}.md"
fi

if [[ "$last_synced" -eq 0 ]]; then
  git_branch="$(jq -r 'select(.gitBranch != null) | .gitBranch' "$transcript_path" | head -1)"
  if [[ "$is_subagent" == "true" ]]; then
    frontmatter="---
session_id: ${session_id}
agent_id: ${agent_id}
agent_type: ${agent_type}
project: ${project}
cwd: ${cwd}
git_branch: ${git_branch}
started_at: ${started_at}
---

"
  else
    frontmatter="---
session_id: ${session_id}
project: ${project}
cwd: ${cwd}
git_branch: ${git_branch}
started_at: ${started_at}
---

"
  fi
  obsidian create vault=obsidian path="$note_path" content="${frontmatter}${chunk}" >/dev/null 2>&1 || true
else
  obsidian append vault=obsidian path="$note_path" content="$chunk" >/dev/null 2>&1 || true
fi

echo "$total_lines" > "$state_file"
