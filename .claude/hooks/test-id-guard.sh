#!/usr/bin/env bash
set -uo pipefail

# id-guard.sh の回帰テスト。
#
#   .claude/hooks/test-id-guard.sh
#
# tool_input を模した JSON を hook に流し込み、宛先ごとに
# deny / ask / noop の判定が期待どおりかを検証する。
# 「誤検知しないこと」（GitHub の #123 参照、UTF-8、裸の UUID など）も見る。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/id-guard.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

REPO_FILE="/Users/example/ghq/github.com/example/app/internal/svc/handler.go"
SKILL_FILE="/Users/example/ghq/github.com/yopiyama/dotfiles/.claude/skills/pr-comments/SKILL.md"

VAULT="$(jq -r '[.vaults[]? | select(.path)] | (map(select(.open == true)) + .) | .[0].path // empty' \
  "$HOME/Library/Application Support/obsidian/obsidian.json" 2>/dev/null)"

pass=0
fail=0
fail_names=()

# judge <hook 出力> → deny|ask|noop|unexpected-output
judge() {
  local output="$1"
  if printf '%s' "$output" | grep -q '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"'; then
    printf 'deny'
  elif printf '%s' "$output" | grep -q '"permissionDecision"[[:space:]]*:[[:space:]]*"ask"'; then
    printf 'ask'
  elif [[ -z "$output" ]]; then
    printf 'noop'
  else
    printf 'unexpected-output'
  fi
}

record() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass=$((pass + 1))
    printf '  ok   %s\n' "$desc"
  else
    fail=$((fail + 1))
    fail_names+=("$desc")
    printf '  FAIL %s (expected=%s actual=%s)\n' "$desc" "$expected" "$actual"
  fi
}

# check_write <説明> <file_path> <content> <expected>
check_write() {
  local desc="$1" path="$2" content="$3" expected="$4" output
  output="$(jq -n --arg p "$path" --arg c "$content" \
    '{tool_name: "Write", tool_input: {file_path: $p, content: $c}}' | "$HOOK" 2>&1)"
  record "$desc" "$expected" "$(judge "$output")"
}

# check_edit <説明> <file_path> <new_string> <expected>
check_edit() {
  local desc="$1" path="$2" new="$3" expected="$4" output
  output="$(jq -n --arg p "$path" --arg n "$new" \
    '{tool_name: "Edit", tool_input: {file_path: $p, old_string: "x", new_string: $n}}' | "$HOOK" 2>&1)"
  record "$desc" "$expected" "$(judge "$output")"
}

# check_bash <説明> <command> <expected>
check_bash() {
  local desc="$1" cmd="$2" expected="$3" output
  output="$(jq -n --arg c "$cmd" \
    '{tool_name: "Bash", tool_input: {command: $c}}' | "$HOOK" 2>&1)"
  record "$desc" "$expected" "$(judge "$output")"
}

# check_mcp <説明> <tool_name> <本文> <expected>
check_mcp() {
  local desc="$1" tool="$2" body="$3" expected="$4" output
  output="$(jq -n --arg t "$tool" --arg b "$body" \
    '{tool_name: $t, tool_input: {pages: [{content: $b}]}}' | "$HOOK" 2>&1)"
  record "$desc" "$expected" "$(judge "$output")"
}

echo "[external: Write/Edit — 検出する]"
check_write "コードに code-review の指摘 ID" "$REPO_FILE" '// P1-1 の指摘に対応' deny
check_write "コードに会話内の通し番号" "$REPO_FILE" '// 指摘 3 の対応。論点2 も含む' deny
check_write "コードに PBI 内のローカル番号" "$REPO_FILE" '// 非機能要件3 を満たすため' deny
check_write "コードに丸数字の要件番号" "$REPO_FILE" '// 受入条件⑥ に対応' deny
check_write "コードに vault の実パス" "$REPO_FILE" '// ClaudeCode/app/Tasks/PR-12/03_foo.md 参照' deny
check_write "コードに session_id" "$REPO_FILE" 'session_id: 2491f878-b440-44ed-ae72-5d46ee4daf55' deny
check_write "コードに pr-comments のタスク連番パス" "$REPO_FILE" '// PR-123/03_ のメモより' deny
check_edit "Edit の new_string に指摘 ID" "$REPO_FILE" '// P2-1 対応' deny

echo "[external: Write/Edit — 誤検知しない]"
check_write "普通のコード" "$REPO_FILE" 'package svc

func Handle() error { return nil }' noop
check_write "GitHub の issue 参照 #123" "$REPO_FILE" '// see #123 for background' noop
check_write "規格名のハイフン付き番号" "$REPO_FILE" '// UTF-8 / SHA-256 / RFC-2119 / ISO-8601' noop
check_write "裸の UUID" "$REPO_FILE" 'const id = "2491f878-b440-44ed-ae72-5d46ee4daf55"' noop
check_write "P1 単体（連番なし）" "$REPO_FILE" '// priority P1 の対応' noop

echo "[exempt: 判定しない宛先]"
check_write "スキル定義内の vault パス（プレースホルダ）" "$SKILL_FILE" \
  'file.inFolder("ClaudeCode/<プロジェクト名>/Tasks/PR-<番号>")' noop
check_write "スキル定義内の指摘 ID の説明" "$SKILL_FILE" '各指摘に P1-1 のような ID を付与する' noop
check_write "memory への書き込み" "$HOME/.claude/projects/x/memory/a.md" 'P1-1 と 非機能要件3' noop
check_write "プランファイルへの書き込み" "$HOME/.claude/plans/foo.md" 'P1-1 と 非機能要件3 を検出する' noop
check_write "scratchpad への書き込み" "/private/tmp/claude-503/x/scratchpad/body.md" 'P1-1 対応' noop
if [[ -n "$VAULT" ]]; then
  check_write "vault への書き込み" "$VAULT/ClaudeCode/a.md" 'P1-1 と 非機能要件3 と 指摘 3' noop
else
  printf '  skip vault への書き込み (vault のパスを解決できず)\n'
fi

echo "[external: Bash]"
check_bash "gh pr comment --body に指摘 ID" \
  'gh pr comment 12 --body "P1-1 を直しました"' deny
check_bash "gh pr comment の heredoc に論点番号" \
  'gh pr comment 12 --body-file - <<EOF
論点2 について補足します
EOF' deny
check_bash "gh pr review に PBI ローカル番号" \
  'gh pr review 12 --comment --body "非機能要件3 の観点で気になります"' deny
check_bash "git commit -m に指摘 ID" \
  'git commit -m "fix: P1-1 の指摘に対応"' deny
check_bash "git commit -m 通常のメッセージ" \
  'git commit -m "fix(svc): nil ハンドラで panic するのを修正"' noop
check_bash "gh pr comment 通常のコメント" \
  'gh pr comment 12 --body "レビューありがとうございます。修正しました"' noop
check_bash "obs.sh への書き込みは素通し" \
  '~/.claude/skills/connect-obsidian/scripts/obs.sh append note.md /tmp/b.md' noop
check_bash "読み取りコマンドは素通し" 'git log --oneline -5 | head' noop
check_bash "指摘 ID を含む grep も素通し" 'rg "P1-1" .' noop

echo "[external: Bash — --body-file の中身も見る]"
BODY_DIRTY="${TMP_ROOT}/dirty.md"
BODY_CLEAN="${TMP_ROOT}/clean.md"
printf '指摘 P3-2 について補足します。\n' >"$BODY_DIRTY"
printf 'レビューありがとうございます。修正しました。\n' >"$BODY_CLEAN"
check_bash "--body-file の本文に指摘 ID" "gh pr comment 12 --body-file $BODY_DIRTY" deny
check_bash "--body-file の本文が綺麗" "gh pr comment 12 --body-file $BODY_CLEAN" noop
check_bash "-F の本文に指摘 ID" "gh issue comment 5 -F $BODY_DIRTY" deny

echo "[notion]"
check_mcp "PBI ローカル番号は Notion では許可" \
  mcp__notion__notion-create-pages '非機能要件3 を満たす実装にしました' noop
check_mcp "指摘 ID は Notion では都度確認" \
  mcp__notion__notion-create-pages '指摘 P1-1 は対応済み' ask
check_mcp "vault パスは Notion では都度確認" \
  mcp__notion__notion-create-pages 'ClaudeCode/app/Tasks/PR-12/03_foo.md にメモ' ask
check_mcp "会話内の通し番号は Notion では都度確認" \
  mcp__notion__notion-update-page '論点2 の結論' ask
check_mcp "普通の本文" \
  mcp__notion__notion-create-pages '実装方針をまとめました' noop
check_mcp "読み取り系ツールは素通し" \
  mcp__notion__notion-fetch '指摘 P1-1 と 非機能要件3' noop

echo "[その他]"
record "対象外のツールは素通し" noop \
  "$(judge "$(jq -n '{tool_name: "Read", tool_input: {file_path: "/x/P1-1.md"}}' | "$HOOK" 2>&1)")"
record "tool_input が空でも落ちない" noop \
  "$(judge "$(jq -n '{tool_name: "Write", tool_input: {}}' | "$HOOK" 2>&1)")"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
if ((fail > 0)); then
  printf 'failed:\n'
  for name in "${fail_names[@]}"; do printf '  - %s\n' "$name"; done
  exit 1
fi
