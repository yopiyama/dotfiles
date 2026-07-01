#!/usr/bin/env bash
set -uo pipefail

# allow-safe-pipes.sh の回帰テスト。
# 実装変更のたびに手動で jq|パイプでケースを叩き直すのが面倒なので、
# これまでの実装・修正セッションで問題になったケースをまとめて再現する。
#
#   .claude/hooks/test-allow-safe-pipes.sh
#
# 各テストは Bash tool_input.command を模した JSON を hook に流し込み、
# 出力に permissionDecision:"allow" が含まれるかどうかで allow/noop を判定する。
# hook は「安全と確認できた時だけ allow を返し、それ以外は何も出力しない」
# 設計 (=noop は「通常のパーミッション確認に委ねる」の意味で、明示的な deny ではない)。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/allow-safe-pipes.sh"

pass=0
fail=0
fail_names=()

# check <説明> <tool_name> <command> <expected: allow|noop>
check() {
  local desc="$1" tool="$2" cmd="$3" expected="$4"
  local output actual

  output="$(jq -n --arg tool "$tool" --arg cmd "$cmd" '{tool_name: $tool, tool_input: {command: $cmd}}' | "$HOOK" 2>&1)"

  if printf '%s' "$output" | grep -q '"permissionDecision"[[:space:]]*:[[:space:]]*"allow"'; then
    actual="allow"
  elif [[ -z "$output" ]]; then
    actual="noop"
  else
    actual="unexpected-output"
  fi

  if [[ "$actual" == "$expected" ]]; then
    pass=$((pass + 1))
    printf '  ok   %s\n' "$desc"
  else
    fail=$((fail + 1))
    fail_names+=("$desc")
    printf '  FAIL %s\n       expected=%s actual=%s\n       cmd=%s\n' "$desc" "$expected" "$actual" "$cmd"
    [[ "$actual" == "unexpected-output" ]] && printf '       output=%s\n' "$output"
  fi
}

echo "=== tool/入力ガード ==="
check "Bash 以外の tool は無視する"                        "Read" "gh api repos/o/r/pulls/1/comments" noop
check "空コマンドは無視する"                                "Bash" "" noop

echo
echo "=== 単純コマンド（複合/パイプ無し）は hook が手を出さない ==="
check "単純な git status は settings.json 側に委ねる (noop)" "Bash" "git status" noop
check "単純な ls -la は settings.json 側に委ねる (noop)"     "Bash" "ls -la" noop

echo
echo "=== gh api: 読み取り専用 (GET/HEAD) は自動承認 ==="
check "gh api 単純GET"                                       "Bash" "gh api repos/o/r/pulls/1/comments" allow
check "gh api -X GET (space区切り、明示)"                     "Bash" "gh api -X GET repos/o/r/pulls/1/comments" allow
check "gh api --method GET (space区切り)"                     "Bash" "gh api --method GET repos/o/r/pulls/1/comments" allow
check "gh api --method=GET (equals区切り)"                    "Bash" "gh api --method=GET repos/o/r/pulls/1/comments" allow
check "gh api -XGET (attached, space無し)"                    "Bash" "gh api repos/o/r/issues -XGET" allow
check "gh api -X HEAD"                                        "Bash" "gh api -X HEAD repos/o/r/pulls/1" allow
check "gh api 引数無し（実行時はエラーになるが判定上は無害）"  "Bash" "gh api" allow

echo
echo "=== gh api: 書き込みを示すフラグがあれば自動承認しない ==="
check "gh api -X POST (space区切り)"                          "Bash" "gh api repos/o/r/pulls/1/comments -X POST -f body=hi" noop
check "gh api -XPOST (attached, space無し) ※過去に誤許可した回帰バグ" "Bash" "gh api repos/o/r/issues -XPOST" noop
check "gh api --method=DELETE (equals区切り)"                 "Bash" "gh api --method=DELETE repos/o/r/issues/1" noop
check "gh api -f による暗黙 POST (space区切り)"                "Bash" "gh api repos/o/r/issues -f title=Bug" noop
check "gh api -ftitle=Bug (attached, space無し) ※過去に誤許可した回帰バグ" "Bash" "gh api repos/o/r/issues -ftitle=Bug" noop
check "gh api -F による typed field"                          "Bash" "gh api repos/o/r/issues -F count=1" noop
check "gh api --input"                                        "Bash" "gh api repos/o/r/contents/f.txt --input body.json" noop
check "gh api graphql -f query=mutation (読み書き判別不能につき拒否)" "Bash" "gh api graphql -f query=mutation" noop
check "gh api graphql -f query=query (読み取りでも -f は一律拒否)"    "Bash" "gh api graphql -f query=query" noop
check "gh api + コマンド置換 (\$())"                          "Bash" "gh api \$(echo repos/o/r/issues) -X DELETE" noop
check "gh api + コマンド置換 (バッククォート)"                 "Bash" 'gh api `echo repos/o/r/issues` -X DELETE' noop
check "gh apiFOO は gh api の前方一致誤爆をしない"             "Bash" "gh apifoo repos/o/r/issues -X DELETE" noop
check "gh api -X だけで値が無い不完全なコマンドは安全側で拒否" "Bash" "gh api repos/o/r/issues -X" noop

echo
echo "=== gh api: パイプ併用でも判定される ==="
check "gh api GET | jq は許可"                                "Bash" "gh api repos/o/r/pulls/1/comments | jq '.[].body'" allow
check "gh api POST | jq はチェーン全体を拒否"                 "Bash" "gh api repos/o/r/pulls/1/comments -X POST -f body=hi | jq ." noop

echo
echo "=== 複合コマンド (&&, ||, ;, リダイレクト) の既存挙動の回帰確認 ==="
check "allow同士の && は許可"                                 "Bash" "git status && ls" allow
check "allow同士の | は許可"                                  "Bash" "git log | head" allow
check "allow同士の ; は許可"                                  "Bash" "git status; git log" allow
check "deny を含む && は拒否 (rm -rf)"                        "Bash" "git status && rm -rf /" noop
check "deny を含む && は拒否 (git push)"                       "Bash" "git status && git push" noop
check "policy に無いコマンドを含む && は拒否"                  "Bash" "git status && npm test" noop
check "deny_pattern (cat *.env) は拒否"                       "Bash" "cat notes.env | grep secret" noop
check "deny_pattern (find -delete) は拒否"                    "Bash" "find . -delete && echo done" noop
check "クォート内のパイプ文字は複合コマンド扱いしない"         "Bash" 'echo "a|b" && git status' allow
check "リダイレクトのみ (>) は許可対象のコマンドなら許可"      "Bash" "git log > /tmp/out.txt" allow
check "追記リダイレクト (>>) も許可対象なら許可"               "Bash" "git log >> /tmp/out.txt" allow
check "stderr リダイレクト (2>&1) も許可対象なら許可"          "Bash" "git status 2>&1" allow

echo
echo "=== 既知の限界 (未対応・意図的にスキップ) ==="
echo "  skip 短縮フラグのクラスタリング (例: -iX POST) は未対応。"
echo "       gh api での実利用頻度が低いため、正規表現/トークン走査では追わず"
echo "       安全側でも危険側でもない未定義動作として残置している。"

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
