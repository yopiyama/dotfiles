#!/usr/bin/env bash
set -uo pipefail

# log-to-obsidian.sh の回帰テスト。
# hook は obsidian CLI を使わず vault へ直接ファイルを書くので、テストも
# 実ファイルシステムで検証する。$HOME をテストごとに隔離ディレクトリへ向け、
# その中にフェイクの vault レジストリ (Library/Application Support/obsidian/
# obsidian.json) とフェイク vault を用意する。state ファイル
# ($HOME/.claude/claude-obsidian-log) も同じ隔離 $HOME に閉じる。
#
#   .claude/hooks/test-log-to-obsidian.sh
#
# 主眼:
# - Stop（メインセッション）と SubagentStop（サブエージェント）が同じ
#   session_id を共有していても、ノート・state ファイルが混ざらないこと
#   （元々このスクリプトを作った動機そのもの）。
# - shell 直書きになったことで、$HOME・バッククォート・クォート・%s・
#   グロブ・改行・非 ASCII などが展開/破壊されずそのまま記録されること。

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
# テストごとに $HOME・vault レジストリ・vault ディレクトリを隔離する。

setup_env() {
  ENV_DIR="$(mktemp -d "$ROOT_DIR/env.XXXXXX")"
  HOME_DIR="$ENV_DIR/home"
  VAULT_DIR="$ENV_DIR/vault/obsidian"
  REGISTRY="$HOME_DIR/Library/Application Support/obsidian/obsidian.json"
  mkdir -p "$HOME_DIR/.claude" "$(dirname "$REGISTRY")" "$VAULT_DIR"
  jq -nc --arg path "$VAULT_DIR" \
    '{vaults:{testvault:{path:$path, ts:1, open:true}}, cli:true}' > "$REGISTRY"
}

run_hook() {
  local json="$1"
  printf '%s' "$json" | HOME="$HOME_DIR" "$HOOK"
}

note_count() {
  find "$VAULT_DIR" -name '*.md' -type f | wc -l | tr -d ' '
}

note_content() {
  cat "$VAULT_DIR/$1" 2>/dev/null
}

# haystack 内に needle が現れる回数
count_occurrences() {
  local haystack="$1" needle="$2"
  printf '%s' "$haystack" | grep -oF "$needle" | wc -l | tr -d ' '
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

NOTE_A="ClaudeCode/myproject/Conversations/202607/2026-07-01T09-00-00_こんにちは.md"
assert_eq          "作成されるノートは1つ"      "1" "$(note_count)"
assert_file_exists "note_path は Conversations/YYYYMM/タイムスタンプ_最初のユーザー発言.md" "$VAULT_DIR/$NOTE_A"
content_a="$(note_content "$NOTE_A")"
assert_contains "frontmatter に session_id"    "$content_a" "session_id: ${SESSION}"
assert_contains "frontmatter に project"       "$content_a" "project: myproject"
assert_contains "frontmatter に git_branch"    "$content_a" "git_branch: main"
assert_not_contains "メインセッションに agent_id は無い" "$content_a" "agent_id:"
assert_contains "User の本文を含む"            "$content_a" "こんにちは"
assert_contains "ツール呼び出しの要約を含む"   "$content_a" "🔧 Read: /tmp/foo.txt"
assert_contains "最終 Assistant の本文を含む"  "$content_a" "読みました"
assert_eq      "state ファイルは全行数"        "3" "$(state_count "$SESSION")"

echo
echo "=== メインセッション (Stop) 2回目: 差分だけ同一ノートに append ==="
{
  line user      "ありがとう"   "2026-07-01T09:01:00.000Z" false false
  line assistant "どういたしまして" "2026-07-01T09:01:01.000Z" false false
} >> "$TR_A"

run_hook "$(hook_input "$SESSION" "$TR_A" "$CWD" Stop)"

assert_eq "ノートは増えない(同一ノートへ append)" "1" "$(note_count)"
content_a2="$(note_content "$NOTE_A")"
assert_contains "append 分の新しい発言を含む"     "$content_a2" "ありがとう"
assert_eq "前回分は重複して書かれない"            "1" "$(count_occurrences "$content_a2" "こんにちは")"
assert_eq "frontmatter も重複しない"              "1" "$(count_occurrences "$content_a2" "session_id:")"
assert_eq "state ファイルは累計行数"              "5" "$(state_count "$SESSION")"

echo
echo "=== サブエージェント (SubagentStop): 親と同じ session_id でも別ノート・別 state ==="
TR_SUB="$ENV_DIR/transcript_sub.jsonl"
{
  line user      "1+1は？"  "2026-07-01T09:05:00.000Z" true false
  line assistant "2です"    "2026-07-01T09:05:01.000Z" true false
} > "$TR_SUB"

run_hook "$(hook_input "$SESSION" "$TR_SUB" "$CWD" SubagentStop "$AGENT" "general-purpose")"

NOTE_SUB="ClaudeCode/myproject/Conversations/202607/SubAgent/2026-07-01T09-05-00_1+1は？_bbbbbbbb.md"
assert_eq          "サブエージェント分のノートが増えて2つ" "2" "$(note_count)"
assert_file_exists "note_path は SubAgent/ 配下+最初のタスク文+agent 8桁" "$VAULT_DIR/$NOTE_SUB"
content_sub="$(note_content "$NOTE_SUB")"
assert_contains "frontmatter に agent_id"   "$content_sub" "agent_id: ${AGENT}"
assert_contains "frontmatter に agent_type" "$content_sub" "agent_type: general-purpose"
assert_contains "isSidechain 行の本文(User)も含む"      "$content_sub" "1+1は？"
assert_contains "isSidechain 行の本文(Assistant)も含む" "$content_sub" "2です"
assert_eq      "サブエージェント用 state ファイルは別キー" "2" "$(state_count "${SESSION}_${AGENT}")"
assert_eq      "親セッションの state ファイルは汚染されない" "5" "$(state_count "$SESSION")"
assert_not_contains "transcript が想定レイアウト外なら親リンクは付かない" "$content_sub" "親セッション"

echo
echo "=== サブエージェント: 親セッションノートへの wikilink を冒頭に付ける ==="
# 実際のレイアウト (<projects>/<session_id>/subagents/agent-<id>.jsonl) を再現。
# 親の Stop はまだ発火しておらず親ノートは未作成、という最頻ケースでも
# 親 transcript から同じノート名を導出してリンクできることを確認する。
setup_env
PROJ_DIR="$ENV_DIR/projects"
mkdir -p "$PROJ_DIR/$SESSION/subagents"
TR_PARENT="$PROJ_DIR/$SESSION.jsonl"
{
  line user      "親の質問" "2026-07-01T18:00:00.000Z" false false
  line assistant "調べます" "2026-07-01T18:00:01.000Z" false false
} > "$TR_PARENT"
TR_SUB_REAL="$PROJ_DIR/$SESSION/subagents/agent-${AGENT:0:8}.jsonl"
{
  line user      "サブタスク" "2026-07-01T18:00:02.000Z" true false
  line assistant "done"       "2026-07-01T18:00:03.000Z" true false
} > "$TR_SUB_REAL"

run_hook "$(hook_input "$SESSION" "$TR_SUB_REAL" "$CWD" SubagentStop "$AGENT" "Explore")"

NOTE_SUB_REAL="ClaudeCode/myproject/Conversations/202607/SubAgent/2026-07-01T18-00-02_サブタスク_bbbbbbbb.md"
assert_file_exists "サブエージェントのノートが作られる" "$VAULT_DIR/$NOTE_SUB_REAL"
content_link="$(note_content "$NOTE_SUB_REAL")"
PARENT_LINK="親セッション: [[ClaudeCode/myproject/Conversations/202607/2026-07-01T18-00-00_親の質問|2026-07-01T18-00-00_親の質問]]"
assert_contains "親ノートへのパス修飾付き wikilink を含む" "$content_link" "$PARENT_LINK"
first_body_line="$(printf '%s\n' "$content_link" | awk '/^---$/{c++; next} c==2 && NF {print; exit}')"
assert_eq "親リンクは frontmatter 直後の先頭行" "$PARENT_LINK" "$first_body_line"
assert_eq "リンク行は作成時のみで重複しない" "1" "$(count_occurrences "$content_link" "親セッション:")"

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
content_d="$(note_content "ClaudeCode/myproject/Conversations/202607/2026-07-01T10-00-00_質問.md")"
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
# ノート名の timestamp は「transcript 先頭の timestamp 付き行」由来なので
# isMeta 行 (11:00:00) の時刻になる。slug は isMeta 除外後の最初のユーザー発話。
content_e="$(note_content "ClaudeCode/myproject/Conversations/202607/2026-07-01T11-00-00_本当の質問.md")"
assert_not_contains "isMeta 行は除外される" "$content_e" "スキル注入テキスト"
assert_contains     "本当の質問は含む"      "$content_e" "本当の質問"

echo
echo "=== 差分が空(isMeta のみ)ならカウントだけ更新しノートは書かない ==="
setup_env
TR_F="$ENV_DIR/transcript_empty_chunk.jsonl"
{
  line assistant "meta only text" "2026-07-01T12:00:00.000Z" false true
} > "$TR_F"

run_hook "$(hook_input "$SESSION" "$TR_F" "$CWD" Stop)"
assert_eq "ノートは作成されない"       "0" "$(note_count)"
assert_eq "state ファイルは更新される" "1" "$(state_count "$SESSION")"

echo
echo "=== 必須フィールド欠如・transcript 不在時は何もしない ==="
setup_env
run_hook "$(hook_input "" "$TR_A" "$CWD" Stop)" || true
assert_eq "session_id が空ならノート無し" "0" "$(note_count)"

run_hook "$(hook_input "$SESSION" "$ENV_DIR/does-not-exist.jsonl" "$CWD" Stop)" || true
assert_eq "transcript_path が存在しないならノート無し" "0" "$(note_count)"

echo
echo "=== 記号・展開されうる文字列が変質せずそのまま記録される ==="
# shell 直書き実装のエスケープ漏れ検出が目的。変数展開・コマンド置換・
# バッククォート・クォート・printf フォーマット・グロブ・履歴展開を混ぜる。
setup_env
DANGEROUS_USER='変数 $HOME ${PATH:-x} とコマンド $(whoami) と `date` を含む発話'
DANGEROUS_ASSIST='printf の %s %d や \n リテラルと "double" '\''single'\'' と !! と * ? [a-z] と ~/ と 🎉絵文字'$'\n実際の改行の2行目\tタブも'
TR_G="$ENV_DIR/transcript_special.jsonl"
{
  line user      "$DANGEROUS_USER"   "2026-07-01T13:00:00.000Z" false false
  line assistant "$DANGEROUS_ASSIST" "2026-07-01T13:00:01.000Z" false false
} > "$TR_G"

run_hook "$(hook_input "$SESSION" "$TR_G" "$CWD" Stop)"

assert_eq "ノートは1つ作成される" "1" "$(note_count)"
note_g="$(find "$VAULT_DIR" -name '*.md' -type f)"
content_g="$(cat "$note_g")"
assert_contains "\$HOME や \${PATH:-x} が展開されない"  "$content_g" '$HOME ${PATH:-x}'
assert_contains "コマンド置換が実行されない"            "$content_g" '$(whoami)'
assert_contains "バッククォートが実行されない"          "$content_g" '`date`'
assert_not_contains "実際の \$HOME 値に化けていない"    "$content_g" "$HOME_DIR"
assert_contains "printf フォーマット文字がそのまま"     "$content_g" '%s %d'
assert_contains "\\n リテラルが改行に化けない"          "$content_g" '\n リテラル'
assert_contains "クォート類がそのまま"                  "$content_g" '"double" '\''single'\'''
assert_contains "履歴展開・グロブ・チルダがそのまま"    "$content_g" '!! と * ? [a-z] と ~/'
assert_contains "絵文字を含む非 ASCII がそのまま"       "$content_g" '🎉絵文字'
assert_contains "本文中の実改行・タブが維持される"      "$content_g" $'実際の改行の2行目\tタブも'

echo
echo "=== ファイル名 slug に記号が入ってもノートを作成できる ==="
setup_env
TR_H="$ENV_DIR/transcript_slugchars.jsonl"
{
  line user      '-rf * $(date) テスト' "2026-07-01T14:00:00.000Z" false false
  line assistant "了解"                 "2026-07-01T14:00:01.000Z" false false
} > "$TR_H"

run_hook "$(hook_input "$SESSION" "$TR_H" "$CWD" Stop)"
assert_file_exists "先頭ハイフン・グロブ・コマンド置換文字入りのファイル名" \
  "$VAULT_DIR/ClaudeCode/myproject/Conversations/202607/"'2026-07-01T14-00-00_-rf * $(date) テスト.md'
assert_eq "スラッシュ入り発話でも slug は _ に置換済み(既存ロジック)" "1" "$(note_count)"

echo
echo "=== vault レジストリ: 複数 vault なら basename=obsidian を優先 ==="
setup_env
OTHER_VAULT="$ENV_DIR/vault_other/notes"
mkdir -p "$OTHER_VAULT"
jq -nc --arg other "$OTHER_VAULT" --arg obs "$VAULT_DIR" \
  '{vaults:{first:{path:$other, ts:1, open:false}, second:{path:$obs, ts:2, open:true}}, cli:true}' \
  > "$REGISTRY"
TR_I="$ENV_DIR/transcript_multivault.jsonl"
{
  line user      "vault選択" "2026-07-01T15:00:00.000Z" false false
  line assistant "ok"        "2026-07-01T15:00:01.000Z" false false
} > "$TR_I"

run_hook "$(hook_input "$SESSION" "$TR_I" "$CWD" Stop)"
assert_eq "obsidian という名前の vault に書かれる" "1" "$(note_count)"
assert_eq "他の vault には書かれない" "0" "$(find "$OTHER_VAULT" -name '*.md' -type f | wc -l | tr -d ' ')"

echo
echo "=== vault レジストリ: basename=obsidian が無ければ先頭の vault にフォールバック ==="
setup_env
jq -nc --arg other "$OTHER_VAULT" \
  '{vaults:{only:{path:$other, ts:1, open:true}}, cli:true}' > "$REGISTRY"
run_hook "$(hook_input "$SESSION" "$TR_I" "$CWD" Stop)"
assert_eq "フォールバック先の vault に書かれる" "1" \
  "$(find "$OTHER_VAULT" -name '*.md' -type f | wc -l | tr -d ' ')"
rm -f "$OTHER_VAULT"/ClaudeCode/myproject/Conversations/*/*.md 2>/dev/null

echo
echo "=== vault レジストリが無い場合は何もしない(state も進めず後で再送できる) ==="
setup_env
rm -f "$REGISTRY"
run_hook "$(hook_input "$SESSION" "$TR_A" "$CWD" Stop)" || true
assert_eq "ノートは作成されない"                 "0" "$(note_count)"
assert_eq "state は更新されない(次回リトライ可)" ""  "$(state_count "$SESSION")"

echo
echo "=== 保存先フォルダはイベント時 cwd ではなくセッション開始時 cwd の git ルート由来 ==="
# ターン途中で cd すると同一セッションのログが別フォルダに分裂していた回帰の防止。
# transcript 先頭行の cwd (サブディレクトリ) から git ルートを解決し、
# イベント時 cwd (無関係なディレクトリ) は無視されることを確認する。
setup_env
REPO_DIR="$ENV_DIR/repos/myrepo"
mkdir -p "$REPO_DIR/subdir" "$ENV_DIR/elsewhere"
git init -q "$REPO_DIR"
TR_J="$ENV_DIR/transcript_cwd.jsonl"
{
  line user      "cd してからの発話" "2026-07-01T16:00:00.000Z" false false \
    | jq -c --arg cwd "$REPO_DIR/subdir" '. + {cwd:$cwd}'
  line assistant "ok"               "2026-07-01T16:00:01.000Z" false false
} > "$TR_J"

run_hook "$(hook_input "$SESSION" "$TR_J" "$ENV_DIR/elsewhere" Stop)"
assert_file_exists "git リポジトリのルート名のフォルダに書かれる" \
  "$VAULT_DIR/ClaudeCode/myrepo/Conversations/202607/2026-07-01T16-00-00_cd してからの発話.md"

echo
echo "=== git 管理外ならセッション開始時 cwd の basename にフォールバック ==="
setup_env
mkdir -p "$ENV_DIR/plaindir" "$ENV_DIR/elsewhere"
TR_K="$ENV_DIR/transcript_cwd_nongit.jsonl"
{
  line user      "git 外の発話" "2026-07-01T17:00:00.000Z" false false \
    | jq -c --arg cwd "$ENV_DIR/plaindir" '. + {cwd:$cwd}'
  line assistant "ok"           "2026-07-01T17:00:01.000Z" false false
} > "$TR_K"

run_hook "$(hook_input "$SESSION" "$TR_K" "$ENV_DIR/elsewhere" Stop)"
assert_file_exists "transcript 先頭の cwd の basename のフォルダに書かれる" \
  "$VAULT_DIR/ClaudeCode/plaindir/Conversations/202607/2026-07-01T17-00-00_git 外の発話.md"

echo
echo "=== 既知の限界 (未対応・意図的にスキップ) ==="
echo "  skip turn_is_complete の 0.2s x 15 回リトライ挙動自体はテストしない。"
echo "       フィクスチャは常に「完了した最終ターン」を満たす形にしてあるため、"
echo "       このテストではリトライループは即座に抜ける想定。"
echo "  skip vault へ直接書いたファイルを Obsidian アプリが検知して表示する挙動は"
echo "       アプリ側の責務なのでテストしない。"

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
