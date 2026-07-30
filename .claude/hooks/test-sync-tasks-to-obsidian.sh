#!/usr/bin/env bash
set -uo pipefail

# sync-tasks-to-obsidian.sh の回帰テスト。
# hook は obsidian CLI を使わず vault へ直接ファイルを書くので、テストも
# 実ファイルシステムで検証する。$HOME をテストごとに隔離ディレクトリへ向け、
# その中にフェイクの vault レジストリ・vault・タスクディレクトリ
# ($HOME/.claude/tasks/<session_id>/)・transcript を用意する。
#
#   .claude/hooks/test-sync-tasks-to-obsidian.sh
#
# 主眼:
# - タスク JSON → チェックリストの変換（status ごとの記号・id 数値順・
#   進捗行・blockedBy 注記・複数行 description）。
# - 毎回の全量書き換えで冪等なこと（再実行してもノートが増殖・重複しない）。
# - ノート名とセッションログへの wikilink が log-to-obsidian.sh の命名と
#   一致すること（obsidian-note-lib.sh の一元管理が保たれていること）。
# - サブエージェント経由の呼び出しでも親セッションのノートに集約すること。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/sync-tasks-to-obsidian.sh"

ROOT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sync-tasks-test.XXXXXX")"
trap 'rm -rf "$ROOT_DIR"' EXIT

pass=0
fail=0
fail_names=()

SESSION="aaaaaaaa-0000-0000-0000-000000000000"
CWD="/Users/tester/myproject"

# --- アサーションヘルパー ---

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass=$((pass + 1))
    printf '  ok   %s\n' "$desc"
  else
    fail=$((fail + 1))
    fail_names+=("$desc")
    printf '  FAIL %s\n       expected=%q\n       actual=%q\n' "$desc" "$expected" "$actual"
  fi
}

assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    pass=$((pass + 1))
    printf '  ok   %s\n' "$desc"
  else
    fail=$((fail + 1))
    fail_names+=("$desc")
    printf '  FAIL %s\n       expected to contain=%q\n       actual=%q\n' "$desc" "$needle" "$haystack"
  fi
}

assert_not_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    pass=$((pass + 1))
    printf '  ok   %s\n' "$desc"
  else
    fail=$((fail + 1))
    fail_names+=("$desc")
    printf '  FAIL %s\n       expected NOT to contain=%q\n       actual=%q\n' "$desc" "$needle" "$haystack"
  fi
}

assert_file_exists() {
  local desc="$1" path="$2"
  if [[ -f "$path" ]]; then
    pass=$((pass + 1))
    printf '  ok   %s\n' "$desc"
  else
    fail=$((fail + 1))
    fail_names+=("$desc")
    printf '  FAIL %s\n       expected file=%q\n' "$desc" "$path"
  fi
}

# --- フィクスチャ生成ヘルパー ---

# transcript_line <user|assistant> <text> <timestamp>
transcript_line() {
  local type="$1" text="$2" ts="$3"
  jq -nc --arg type "$type" --arg text "$text" --arg ts "$ts" --arg cwd "$CWD" '
    {type:$type, timestamp:$ts, isSidechain:false, isMeta:false, cwd:$cwd,
     message:{role:$type, content:$text}}'
}

# task_json <id> <status> <subject> [description] [blockedBy_json]
# $TASKS_DIR/<id>.json に実物と同じ形のタスクファイルを書く。
task_json() {
  local id="$1" status="$2" subject="$3" description="${4:-}" blocked_by="${5:-[]}"
  jq -n --arg id "$id" --arg status "$status" --arg subject "$subject" \
    --arg description "$description" --argjson blockedBy "$blocked_by" '
    {id:$id, subject:$subject, description:$description, activeForm:"",
     status:$status, blocks:[], blockedBy:$blockedBy}' > "$TASKS_DIR/$id.json"
}

# hook_input [transcript_path]
hook_input() {
  local transcript="${1:-$TRANSCRIPT}"
  jq -nc --arg session_id "$SESSION" --arg transcript "$transcript" --arg cwd "$CWD" '
    {session_id:$session_id, transcript_path:$transcript, cwd:$cwd,
     hook_event_name:"PostToolUse", tool_name:"TaskUpdate",
     tool_input:{taskId:"1", status:"in_progress"}}'
}

# --- 実行環境のセットアップ ---
# テストごとに $HOME・vault・タスクディレクトリ・transcript を隔離する。

setup_env() {
  ENV_DIR="$(mktemp -d "$ROOT_DIR/env.XXXXXX")"
  HOME_DIR="$ENV_DIR/home"
  VAULT_DIR="$ENV_DIR/vault/obsidian"
  REGISTRY="$HOME_DIR/Library/Application Support/obsidian/obsidian.json"
  TASKS_DIR="$HOME_DIR/.claude/tasks/$SESSION"
  TRANSCRIPT="$ENV_DIR/transcript.jsonl"
  mkdir -p "$TASKS_DIR" "$(dirname "$REGISTRY")" "$VAULT_DIR"
  jq -nc --arg path "$VAULT_DIR" \
    '{vaults:{testvault:{path:$path, ts:1, open:true}}, cli:true}' > "$REGISTRY"
  {
    transcript_line user      "タスク管理のテスト" "2026-07-02T09:00:00.000Z"
    transcript_line assistant "やります"           "2026-07-02T09:00:01.000Z"
  } > "$TRANSCRIPT"
}

run_hook() {
  local json="$1"
  printf '%s' "$json" | HOME="$HOME_DIR" "$HOOK"
}

note_count() {
  find "$VAULT_DIR" -name '*.md' -type f | wc -l | tr -d ' '
}

NOTE_REL="ClaudeCode/myproject/Tasks/202607/2026-07-02T09-00-00_タスク管理のテスト.md"

note_content() {
  cat "$VAULT_DIR/$NOTE_REL" 2>/dev/null
}

count_occurrences() {
  local haystack="$1" needle="$2"
  printf '%s' "$haystack" | grep -oF "$needle" | wc -l | tr -d ' '
}

echo "=== 基本: status ごとの記号・進捗行・セッションログへの wikilink ==="
setup_env
task_json 1 completed   "調査する"   "フォーマットを確認する"
task_json 2 in_progress "実装する"
task_json 3 pending     "テストする"

run_hook "$(hook_input)"

assert_eq          "作成されるノートは1つ" "1" "$(note_count)"
assert_file_exists "ノートは Tasks/YYYYMM/ 配下にセッションノートと同名" "$VAULT_DIR/$NOTE_REL"
content="$(note_content)"
assert_contains "frontmatter に session_id"        "$content" "session_id: ${SESSION}"
assert_contains "frontmatter に project"           "$content" "project: myproject"
assert_contains "セッションログへのパス修飾付き wikilink" "$content" \
  "セッションログ: [[ClaudeCode/myproject/Conversations/202607/2026-07-02T09-00-00_タスク管理のテスト|2026-07-02T09-00-00_タスク管理のテスト]]"
assert_contains "進捗行 (完了数/総数)"             "$content" "進捗: 1/3 完了"
assert_contains "completed は - [x]"               "$content" "- [x] #1 調査する"
assert_contains "in_progress は - [/] と太字"      "$content" "- [/] #2 **実装する**"
assert_contains "pending は - [ ]"                 "$content" "- [ ] #3 テストする"
assert_contains "description は引用でネストされる" "$content" "    > フォーマットを確認する"

echo
echo "=== 再実行・status 更新: 全量書き換えで冪等、増殖しない ==="
task_json 2 completed "実装する"
task_json 3 in_progress "テストする"

run_hook "$(hook_input)"
run_hook "$(hook_input)"

assert_eq "ノートは増えない" "1" "$(note_count)"
content2="$(note_content)"
assert_contains "更新後の進捗行"                "$content2" "進捗: 2/3 完了"
assert_contains "status 変更が反映される"       "$content2" "- [x] #2 実装する"
assert_eq "frontmatter が重複しない"            "1" "$(count_occurrences "$content2" "session_id:")"
assert_eq "タスク行が重複しない"                "1" "$(count_occurrences "$content2" "#2 実装する")"
assert_eq "wikilink が重複しない"               "1" "$(count_occurrences "$content2" "セッションログ:")"

echo
echo "=== id は数値順に並ぶ (2 < 9 < 10、辞書順の 10 < 2 < 9 にならない) ==="
setup_env
task_json 10 pending "十番目"
task_json 2  pending "二番目"
task_json 9  pending "九番目"

run_hook "$(hook_input)"
content_order="$(note_content | grep -F -- '- [ ]' | tr '\n' '|')"
assert_eq "数値順 2,9,10" "- [ ] #2 二番目|- [ ] #9 九番目|- [ ] #10 十番目|" "$content_order"

echo
echo "=== deleted の JSON が残っていても表示しない・削除は次回同期で消える ==="
setup_env
task_json 1 pending "残るタスク"
task_json 2 deleted "消えたタスク"
task_json 3 pending "ファイルごと消すタスク"

run_hook "$(hook_input)"
content_del="$(note_content)"
assert_contains     "通常タスクは表示される"      "$content_del" "残るタスク"
assert_not_contains "status=deleted は表示しない" "$content_del" "消えたタスク"
assert_contains     "進捗の分母にも数えない"      "$content_del" "進捗: 0/2 完了"

rm "$TASKS_DIR/3.json"
run_hook "$(hook_input)"
assert_not_contains "JSON ファイル削除も次回同期で反映" "$(note_content)" "ファイルごと消すタスク"

echo
echo "=== blockedBy は注記として付く ==="
setup_env
task_json 1 pending "先行タスク"
task_json 2 pending "後続タスク" "" '["1"]'

run_hook "$(hook_input)"
assert_contains "blockedBy 注記" "$(note_content)" "- [ ] #2 後続タスク（⏳ #1 待ち）"

echo
echo "=== 複数行 description は全行引用でネストされる ==="
setup_env
task_json 1 pending "複数行" $'1行目\n2行目'

run_hook "$(hook_input)"
content_ml="$(note_content)"
assert_contains "1行目が引用される" "$content_ml" "    > 1行目"
assert_contains "2行目も引用される" "$content_ml" "    > 2行目"

echo
echo "=== 記号・展開されうる文字列が変質せずそのまま記録される ==="
setup_env
task_json 1 pending '変数 $HOME と $(whoami) と `date` と %s を含む subject' '"double" と * ? [a-z] と 🎉'

run_hook "$(hook_input)"
content_sp="$(note_content)"
assert_contains "\$HOME・コマンド置換・バッククォート・%s がそのまま" "$content_sp" \
  '変数 $HOME と $(whoami) と `date` と %s を含む subject'
assert_contains "description の記号・絵文字もそのまま" "$content_sp" '"double" と * ? [a-z] と 🎉'
assert_not_contains "実際の \$HOME 値に化けていない" "$content_sp" "$HOME_DIR"

echo
echo "=== サブエージェント経由でも親セッションのタスクノートに集約する ==="
setup_env
task_json 1 in_progress "サブエージェントが進めるタスク"
PROJ_DIR="$ENV_DIR/projects"
mkdir -p "$PROJ_DIR/$SESSION/subagents"
cp "$TRANSCRIPT" "$PROJ_DIR/$SESSION.jsonl"
TRANSCRIPT="$PROJ_DIR/$SESSION.jsonl"
TR_SUB="$PROJ_DIR/$SESSION/subagents/agent-bbbbbbbb.jsonl"
{
  transcript_line user      "サブタスク" "2026-07-02T09:05:00.000Z"
  transcript_line assistant "done"       "2026-07-02T09:05:01.000Z"
} > "$TR_SUB"

run_hook "$(hook_input "$TR_SUB")"
assert_eq          "ノートは親セッション分の1つだけ" "1" "$(note_count)"
assert_file_exists "親 transcript 由来の名前になる" "$VAULT_DIR/$NOTE_REL"

echo
echo "=== タスクが無い・環境が欠けている場合は何もしない ==="
setup_env
run_hook "$(hook_input)" || true
assert_eq "タスク JSON が無ければノート無し" "0" "$(note_count)"

setup_env
task_json 1 pending "タスク"
rm "$REGISTRY"
run_hook "$(hook_input)" || true
assert_eq "vault レジストリが無ければノート無し" "0" "$(note_count)"

setup_env
task_json 1 pending "タスク"
run_hook "$(hook_input "$ENV_DIR/does-not-exist.jsonl")" || true
assert_eq "transcript が無ければノート無し" "0" "$(note_count)"

setup_env
task_json 1 pending "タスク"
json_no_session="$(jq -nc --arg transcript "$TRANSCRIPT" --arg cwd "$CWD" '
  {transcript_path:$transcript, cwd:$cwd, hook_event_name:"PostToolUse", tool_name:"TaskCreate"}')"
run_hook "$json_no_session" || true
assert_eq "session_id が無ければノート無し" "0" "$(note_count)"

echo
echo "=== 既知の限界 (未対応・意図的にスキップ) ==="
echo "  skip 並行フック起動の競合は temp file + mv のアトミック置換に任せ、"
echo "       タイミング依存のテストはしない (最後の書き込みが勝てばよい)。"
echo "  skip ノート名の元になるセッションログ側の命名変更への追従は"
echo "       obsidian-note-lib.sh の共有で担保する (test-log-to-obsidian.sh 側)。"

echo
echo "=== 結果: pass=$pass fail=$fail ==="
if [[ "$fail" -gt 0 ]]; then
  echo "failed:"
  for name in "${fail_names[@]}"; do
    echo "  - $name"
  done
  exit 1
fi
exit 0
