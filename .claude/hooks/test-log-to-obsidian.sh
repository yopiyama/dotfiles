#!/usr/bin/env bash
set -uo pipefail

# log-to-obsidian.sh の回帰テスト。
# 実際の obsidian CLI は叩かず、PATH に差し込んだフェイクの `obsidian` が
# 呼び出し引数をファイルに記録するだけにする。$HOME もテストごとに隔離した
# ディレクトリへ向け、$HOME/.claude/claude-obsidian-log 配下の state ファイル
# が本物の状態と混ざらないようにする。
#
#   .claude/hooks/test-log-to-obsidian.sh
#
# 主眼は「Stop（メインセッション）と SubagentStop（サブエージェント）が
# 同じ session_id を共有していても、ノート・state ファイルが混ざらない
# こと」の回帰確認（元々このスクリプトを作った動機そのもの）。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/log-to-obsidian.sh"

ROOT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/log-to-obsidian-test.XXXXXX")"
trap 'rm -rf "$ROOT_DIR"' EXIT

pass=0
fail=0
fail_names=()

SESSION="aaaaaaaa-0000-0000-0000-000000000000"
AGENT="bbbbbbbb-1111-1111-1111-111111111111"
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

# --- フィクスチャ生成ヘルパー ---

# line <user|assistant> <text> <timestamp> <isSidechain:true|false> <isMeta:true|false> [tool_name] [tool_input_json]
# 1行分の transcript JSON を標準出力に書く。
line() {
  local type="$1" text="$2" ts="$3" sidechain="$4" meta="$5" tool_name="${6:-}" tool_input="${7:-}"
  if [[ "$type" == "user" ]]; then
    jq -nc --arg text "$text" --arg ts "$ts" --argjson sidechain "$sidechain" --argjson meta "$meta" '
      {type:"user", timestamp:$ts, isSidechain:$sidechain, isMeta:$meta, gitBranch:"main",
       message:{role:"user", content:$text}}'
  elif [[ -n "$tool_name" ]]; then
    jq -nc --arg text "$text" --arg ts "$ts" --argjson sidechain "$sidechain" --argjson meta "$meta" \
      --arg tool_name "$tool_name" --argjson tool_input "$tool_input" '
      {type:"assistant", timestamp:$ts, isSidechain:$sidechain, isMeta:$meta, gitBranch:"main",
       message:{role:"assistant", content:
         ( (if ($text|length)>0 then [{type:"text", text:$text}] else [] end)
           + [{type:"tool_use", name:$tool_name, input:$tool_input}] )}}'
  else
    jq -nc --arg text "$text" --arg ts "$ts" --argjson sidechain "$sidechain" --argjson meta "$meta" '
      {type:"assistant", timestamp:$ts, isSidechain:$sidechain, isMeta:$meta, gitBranch:"main",
       message:{role:"assistant", content:[{type:"text", text:$text}]}}'
  fi
}

# hook_input <session_id> <transcript_path> <cwd> [hook_event_name] [agent_id] [agent_type]
hook_input() {
  local session_id="$1" transcript="$2" cwd="$3" event="${4:-Stop}" agent_id="${5:-}" agent_type="${6:-}"
  jq -nc --arg session_id "$session_id" --arg transcript "$transcript" --arg cwd "$cwd" \
    --arg event "$event" --arg agent_id "$agent_id" --arg agent_type "$agent_type" '
    {session_id:$session_id, transcript_path:$transcript, cwd:$cwd, hook_event_name:$event}
    + (if $agent_id   != "" then {agent_id:$agent_id}     else {} end)
    + (if $agent_type != "" then {agent_type:$agent_type} else {} end)
  '
}

# --- 実行環境のセットアップ ---
# テストごとに $HOME・呼び出し記録先・obsidian フェイクを隔離する。

setup_env() {
  ENV_DIR="$(mktemp -d "$ROOT_DIR/env.XXXXXX")"
  HOME_DIR="$ENV_DIR/home"
  BIN_DIR="$ENV_DIR/bin"
  CALLS_DIR="$ENV_DIR/calls"
  mkdir -p "$HOME_DIR/.claude" "$BIN_DIR" "$CALLS_DIR"
  cat > "$BIN_DIR/obsidian" <<'EOS'
#!/usr/bin/env bash
n=0
for f in "$CALLS_DIR"/call_*; do [[ -e "$f" ]] && n=$((n + 1)); done
call_dir="$CALLS_DIR/call_${n}"
mkdir -p "$call_dir"
i=0
for a in "$@"; do
  printf '%s' "$a" > "$call_dir/arg_${i}"
  i=$((i + 1))
done
exit 0
EOS
  chmod +x "$BIN_DIR/obsidian"
}

run_hook() {
  local json="$1"
  printf '%s' "$json" | HOME="$HOME_DIR" CALLS_DIR="$CALLS_DIR" PATH="$BIN_DIR:$PATH" "$HOOK"
}

call_count() {
  local n=0 f
  for f in "$CALLS_DIR"/call_*; do [[ -e "$f" ]] && n=$((n + 1)); done
  echo "$n"
}

call_arg() {
  local idx="$1" argnum="$2"
  cat "$CALLS_DIR/call_${idx}/arg_${argnum}" 2>/dev/null
}

state_count() {
  cat "$HOME_DIR/.claude/claude-obsidian-log/$1.count" 2>/dev/null
}

echo "=== メインセッション (Stop): 新規ノート作成 ==="
setup_env
TR_A="$ENV_DIR/transcript.jsonl"
{
  line user      "こんにちは"   "2026-07-01T09:00:00.000Z" false false
  line assistant ""            "2026-07-01T09:00:01.000Z" false false "Read" '{"file_path":"/tmp/foo.txt"}'
  line assistant "読みました"   "2026-07-01T09:00:02.000Z" false false
} > "$TR_A"

run_hook "$(hook_input "$SESSION" "$TR_A" "$CWD" Stop)"

assert_eq      "obsidian 呼び出しは1回"        "1" "$(call_count)"
assert_eq      "1回目は create"                "create" "$(call_arg 0 0)"
assert_eq      "note_path はタイムスタンプ_最初のユーザー発言.md" \
  "path=ClaudeCode/myproject/2026-07-01T09-00-00_こんにちは.md" "$(call_arg 0 2)"
content_a="$(call_arg 0 3)"
assert_contains "frontmatter に session_id"    "$content_a" "session_id: ${SESSION}"
assert_contains "frontmatter に project"       "$content_a" "project: myproject"
assert_contains "frontmatter に git_branch"    "$content_a" "git_branch: main"
assert_not_contains "メインセッションに agent_id は無い" "$content_a" "agent_id:"
assert_contains "User の本文を含む"            "$content_a" "こんにちは"
assert_contains "ツール呼び出しの要約を含む"   "$content_a" "🔧 Read: /tmp/foo.txt"
assert_contains "最終 Assistant の本文を含む"  "$content_a" "読みました"
assert_eq      "state ファイルは全行数"        "3" "$(state_count "$SESSION")"

echo
echo "=== メインセッション (Stop) 2回目: 差分だけ append ==="
{
  line user      "ありがとう"   "2026-07-01T09:01:00.000Z" false false
  line assistant "どういたしまして" "2026-07-01T09:01:01.000Z" false false
} >> "$TR_A"

run_hook "$(hook_input "$SESSION" "$TR_A" "$CWD" Stop)"

assert_eq      "2回目の呼び出しで合計2回"      "2" "$(call_count)"
assert_eq      "2回目は append"                "append" "$(call_arg 1 0)"
assert_eq      "append 先の note_path は1回目と同じ" \
  "path=ClaudeCode/myproject/2026-07-01T09-00-00_こんにちは.md" "$(call_arg 1 2)"
content_a2="$(call_arg 1 3)"
assert_contains    "append 分に新しい発言を含む" "$content_a2" "ありがとう"
assert_not_contains "append 分に前回分は重複しない" "$content_a2" "こんにちは"
assert_eq      "state ファイルは累計行数"      "5" "$(state_count "$SESSION")"

echo
echo "=== サブエージェント (SubagentStop): 親と同じ session_id でも別ノート・別 state ==="
TR_SUB="$ENV_DIR/transcript_sub.jsonl"
{
  line user      "1+1は？"  "2026-07-01T09:05:00.000Z" true false
  line assistant "2です"    "2026-07-01T09:05:01.000Z" true false
} > "$TR_SUB"

run_hook "$(hook_input "$SESSION" "$TR_SUB" "$CWD" SubagentStop "$AGENT" "general-purpose")"

assert_eq      "サブエージェント分もあわせて3回目の呼び出し" "3" "$(call_count)"
assert_eq      "サブエージェントの初回も create"              "create" "$(call_arg 2 0)"
assert_eq      "note_path は最初のタスク文+agent 8桁" \
  "path=ClaudeCode/myproject/2026-07-01T09-05-00_1+1は？_bbbbbbbb.md" "$(call_arg 2 2)"
content_sub="$(call_arg 2 3)"
assert_contains "frontmatter に agent_id"   "$content_sub" "agent_id: ${AGENT}"
assert_contains "frontmatter に agent_type" "$content_sub" "agent_type: general-purpose"
assert_contains "isSidechain 行の本文(User)も含む"      "$content_sub" "1+1は？"
assert_contains "isSidechain 行の本文(Assistant)も含む" "$content_sub" "2です"
assert_eq      "サブエージェント用 state ファイルは別キー" "2" "$(state_count "${SESSION}_${AGENT}")"
assert_eq      "親セッションの state ファイルは汚染されない" "5" "$(state_count "$SESSION")"

echo
echo "=== メインセッション (Stop) は isSidechain 行を除外する ==="
setup_env
TR_D="$ENV_DIR/transcript_sidechain.jsonl"
{
  line user      "質問"                       "2026-07-01T10:00:00.000Z" false false
  line user      "サブエージェントへの委譲文" "2026-07-01T10:00:01.000Z" true  false
  line assistant "回答"                       "2026-07-01T10:00:02.000Z" false false
} > "$TR_D"

run_hook "$(hook_input "$SESSION" "$TR_D" "$CWD" Stop)"
content_d="$(call_arg 0 3)"
assert_contains     "通常行(質問)は含む"        "$content_d" "質問"
assert_contains     "通常行(回答)は含む"        "$content_d" "回答"
assert_not_contains "isSidechain 行は除外される" "$content_d" "サブエージェントへの委譲文"

echo
echo "=== isMeta の行は除外される ==="
setup_env
TR_E="$ENV_DIR/transcript_meta.jsonl"
{
  line user      "スキル注入テキスト" "2026-07-01T11:00:00.000Z" false true
  line user      "本当の質問"         "2026-07-01T11:00:01.000Z" false false
  line assistant "回答"               "2026-07-01T11:00:02.000Z" false false
} > "$TR_E"

run_hook "$(hook_input "$SESSION" "$TR_E" "$CWD" Stop)"
content_e="$(call_arg 0 3)"
assert_not_contains "isMeta 行は除外される" "$content_e" "スキル注入テキスト"
assert_contains     "本当の質問は含む"      "$content_e" "本当の質問"

echo
echo "=== 差分が空(isMeta のみ)ならカウントだけ更新し obsidian は呼ばない ==="
setup_env
TR_F="$ENV_DIR/transcript_empty_chunk.jsonl"
{
  line assistant "meta only text" "2026-07-01T12:00:00.000Z" false true
} > "$TR_F"

run_hook "$(hook_input "$SESSION" "$TR_F" "$CWD" Stop)"
assert_eq "obsidian は呼ばれない"     "0" "$(call_count)"
assert_eq "state ファイルは更新される" "1" "$(state_count "$SESSION")"

echo
echo "=== 必須フィールド欠如・transcript 不在時は何もしない ==="
setup_env
run_hook "$(hook_input "" "$TR_A" "$CWD" Stop)" || true
assert_eq "session_id が空なら呼び出し無し" "0" "$(call_count)"

run_hook "$(hook_input "$SESSION" "$ENV_DIR/does-not-exist.jsonl" "$CWD" Stop)" || true
assert_eq "transcript_path が存在しないなら呼び出し無し" "0" "$(call_count)"

echo
echo "=== 既知の限界 (未対応・意図的にスキップ) ==="
echo "  skip turn_is_complete の 0.2s x 15 回リトライ挙動自体はテストしない。"
echo "       フィクスチャは常に「完了した最終ターン」を満たす形にしてあるため、"
echo "       このテストではリトライループは即座に抜ける想定。"
echo "  skip 実際の obsidian CLI 呼び出しの成否は検証しない(フェイクは常に成功扱い)。"

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
