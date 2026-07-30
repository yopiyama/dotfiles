#!/usr/bin/env bash
set -uo pipefail

# git-guard.sh の回帰テスト。
#
#   .claude/hooks/test-git-guard.sh
#
# 一時ディレクトリに「仕事リポジトリ」(remote が yopiyama 配下以外の組織) と
# 「個人リポジトリ」(remote が yopiyama 配下) の fixture を作り、
# Bash tool_input.command を模した JSON を hook に流し込んで
# deny / ask / noop の判定を検証する。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/git-guard.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

WORK="${TMP_ROOT}/work-repo"
PERSONAL="${TMP_ROOT}/personal-repo"

setup_repo() {
  local dir="$1" remote_url="$2"
  mkdir -p "$dir"
  git -C "$dir" init -q -b main
  git -C "$dir" remote add origin "$remote_url"
  git -C "$dir" -c user.name=test -c user.email=test@example.com \
    commit -q --allow-empty -m init
}

setup_repo "$WORK" "git@github.com:example-corp/some-app.git"
setup_repo "$PERSONAL" "git@github.com:yopiyama/mytool.git"

pass=0
fail=0
fail_names=()

# check <説明> <command> <expected: deny|ask|noop> <cwd>
check() {
  local desc="$1" cmd="$2" expected="$3" cwd="$4"
  local output actual

  output="$(jq -n --arg cmd "$cmd" --arg cwd "$cwd" \
    '{tool_name: "Bash", tool_input: {command: $cmd}, cwd: $cwd}' \
    | "$HOOK" 2>&1)"

  if printf '%s' "$output" | grep -q '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"'; then
    actual="deny"
  elif printf '%s' "$output" | grep -q '"permissionDecision"[[:space:]]*:[[:space:]]*"ask"'; then
    actual="ask"
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
out="$(jq -n '{tool_name: "Read", tool_input: {file_path: "/x"}}' | "$HOOK" 2>&1)"
if [[ -z "$out" ]]; then
  pass=$((pass + 1)); printf '  ok   Bash 以外の tool は無視する\n'
else
  fail=$((fail + 1)); fail_names+=("Bash 以外の tool は無視する")
  printf '  FAIL Bash 以外の tool は無視する\n       output=%s\n' "$out"
fi
check "空コマンドは無視する"                     ""        noop "$WORK"
check "git 以外のコマンドは無視する"             "ls -la"  noop "$WORK"
check "echo に git push が含まれても誤検知しない" "echo git push origin main" noop "$WORK"

echo
echo "=== git push: 仕事リポジトリ (yopiyama 配下以外) ==="
check "main への明示 push は deny"                "git push origin main"          deny "$WORK"
check "refspec 省略 (current=main) も deny"       "git push"                      deny "$WORK"
check "HEAD:main 形式も deny"                     "git push origin HEAD:main"     deny "$WORK"
check "main への force push は deny"              "git push --force origin main"  deny "$WORK"
check "+refspec (force 相当) も deny"             "git push origin +main"         deny "$WORK"
check "feature ブランチへの push は noop"         "git push origin feature/foo"   noop "$WORK"
check "feature への force push は ask"            "git push -f origin feature/foo" ask "$WORK"
check "--force-with-lease も force 扱いで ask"    "git push --force-with-lease origin feature/foo" ask "$WORK"

echo
echo "=== git push: 個人リポジトリ (github.com/yopiyama/) ==="
check "main への push は ask に緩和"              "git push origin main"          ask  "$PERSONAL"
check "feature ブランチへの push は noop"         "git push origin feature/foo"   noop "$PERSONAL"

echo
echo "=== git push: 破壊的フラグは常に deny ==="
check "--mirror は deny"                          "git push --mirror backup"      deny "$WORK"
check "--delete は deny"                          "git push --delete origin foo"  deny "$WORK"
check "-d は deny"                                "git push -d origin foo"        deny "$WORK"

echo
echo "=== git reset ==="
check "reset --hard (クリーン) は ask"            "git reset --hard HEAD~1"       ask  "$WORK"
check "reset --merge (クリーン) は ask"           "git reset --merge HEAD~1"      ask  "$WORK"
check "reset --soft は noop"                      "git reset --soft HEAD~1"       noop "$WORK"
check "reset --mixed / パス指定は noop"           "git reset HEAD file.txt"       noop "$WORK"

touch "${WORK}/dirty.txt"
check "reset --hard (未コミット変更あり) は deny" "git reset --hard"              deny "$WORK"
rm -f "${WORK}/dirty.txt"

echo
echo "=== 複合コマンド・変則形式 ==="
check "&& で繋いだ push も検査する"               "cd sub && git push origin main"       deny "$WORK"
check "; で繋いだ reset --hard も検査する"        "git fetch; git reset --hard origin/main" ask "$WORK"
check "env 変数プレフィックス付きも検査する"      "GIT_TRACE=1 git push origin main"     deny "$WORK"
check "git -C <path> push も path 側で判定する"   "git -C ${WORK} push origin main"      deny "$PERSONAL"
check "deny > ask: 複合内に deny があれば deny"   "git push origin main && git push -f origin feature/foo" deny "$WORK"

echo
if [[ "$fail" -eq 0 ]]; then
  printf 'ALL PASS (%d tests)\n' "$pass"
else
  printf 'FAIL: %d/%d\n' "$fail" $((pass + fail))
  for name in "${fail_names[@]}"; do
    printf '  - %s\n' "$name"
  done
  exit 1
fi
