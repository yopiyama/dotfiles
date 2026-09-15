#!/usr/bin/env bash
# projects.json の既存プロファイルを Herdr workspace/tab/pane として開く。
# tmux の launch_project.sh と同じ JSON を入力にするため、プロファイル定義は共用する。
set -euo pipefail

CONFIG="${TMUX_PROJECTS_JSON:-$HOME/.tmux/projects.json}"
HERDR_BIN="${HERDR_BIN_PATH:-herdr}"
HERDR_MIN_VERSION="0.9.0"
US=$'\x1f'

die() {
  echo "launch_project (herdr): $*" >&2
  exit 1
}

split_ratio_args() {
  local size="$1" percent ratio
  case "$size" in
    *%)
      percent="${size%%%}"
      ratio="$(awk -v p="$percent" 'BEGIN { printf "%.6f", 1 - (p / 100) }')"
      case "$ratio" in
        0.*|1.000000) printf '%s\n' "$ratio" ;;
      esac
      ;;
  esac
}

command -v jq >/dev/null || die "jq が必要です"
command -v fzf >/dev/null || die "fzf が必要です"
command -v "$HERDR_BIN" >/dev/null || die "herdr が必要です"
herdr_version="$("$HERDR_BIN" --version 2>/dev/null \
  | sed -nE 's/^herdr ([0-9]+\.[0-9]+\.[0-9]+).*/\1/p')"
[ -n "$herdr_version" ] || die "herdr のバージョンを取得できませんでした"
awk -F. -v actual="$herdr_version" -v required="$HERDR_MIN_VERSION" '
  BEGIN {
    split(actual, a); split(required, r)
    if (a[1] > r[1] || (a[1] == r[1] && a[2] > r[2]) ||
        (a[1] == r[1] && a[2] == r[2] && a[3] >= r[3])) exit 0
    exit 1
  }
' || die "Herdr $HERDR_MIN_VERSION 以上が必要です (現在: $herdr_version)"
[ -f "$CONFIG" ] || die "$CONFIG が見つかりません (projects.json.sample をコピーしてください)"
jq empty "$CONFIG" >/dev/null 2>&1 || die "$CONFIG が壊れています (JSON として読めません)"

list="$(jq -r '.projects[] | "\(.name)\t\(.path)"' "$CONFIG")"
[ -n "$list" ] || die "projects.json の projects[] が空です"

selected="$(printf '%s\n' "$list" \
  | fzf --delimiter='\t' --with-nth=1,2 \
        --prompt='project> ' \
        --header='Enter: open / attach   Esc: cancel' \
        --no-multi
)" || selected=""

name="${selected%%$'\t'*}"
[ -n "$name" ] || exit 0

path="$(jq -r --arg n "$name" '.projects[] | select(.name==$n) | .path' "$CONFIG")"
path="${path/#\~/$HOME}"
[ -d "$path" ] || die "ディレクトリが存在しません: $path"

# projects.json は同じ path に複数 profile を許すため、label と cwd の組で照合する。
workspace_id="$("$HERDR_BIN" workspace list 2>/dev/null \
  | jq -r --arg n "$name" --arg p "$path" \
      '[.result.workspaces[] | select(.label == $n and .cwd == $p) | .workspace_id] | first // empty' \
  || true)"

if [ -n "$workspace_id" ]; then
  "$HERDR_BIN" workspace focus "$workspace_id" >/dev/null
  exit 0
fi

records="$(jq -r --arg n "$name" '
  (.defaults.windows // []) as $d
  | .projects[] | select(.name==$n)
  | (.windows // $d)[]
  | "window\u001f\(.name)\u001f\(.cmd // "")",
    ((.panes // [])[]
     | "pane\u001f\(.split // "bottom")\u001f\(.size // "")\u001f\(.cmd // "")")
' "$CONFIG")"
[ -n "$records" ] || die "$name のウィンドウ定義が空です"

created="$("$HERDR_BIN" workspace create --cwd "$path" --label "$name" --no-focus)" \
  || die "workspace を作成できませんでした: $name"
workspace_id="$(printf '%s\n' "$created" | jq -r '.result.workspace.workspace_id // empty')"
tab_id="$(printf '%s\n' "$created" | jq -r '.result.tab.tab_id // empty')"
pane_id="$(printf '%s\n' "$created" | jq -r '.result.root_pane.pane_id // empty')"
[ -n "$workspace_id" ] && [ -n "$tab_id" ] && [ -n "$pane_id" ] \
  || die "workspace create の応答から ID を取得できませんでした"

first_window=1
while IFS="$US" read -r kind f1 f2 f3; do
  case "$kind" in
    window)
      if [ "$first_window" -eq 1 ]; then
        first_window=0
      else
        created_tab="$("$HERDR_BIN" tab create --workspace "$workspace_id" \
          --cwd "$path" --label "$f1" --no-focus)" \
          || die "tab を作成できませんでした: $f1"
        tab_id="$(printf '%s\n' "$created_tab" | jq -r '.result.tab.tab_id // empty')"
        pane_id="$(printf '%s\n' "$created_tab" | jq -r '.result.root_pane.pane_id // empty')"
        [ -n "$tab_id" ] && [ -n "$pane_id" ] || die "tab create の応答から ID を取得できませんでした"
      fi
      "$HERDR_BIN" tab rename "$tab_id" "$f1" >/dev/null
      [ -n "$f2" ] && "$HERDR_BIN" pane run "$pane_id" "$f2" >/dev/null
      ;;
    pane)
      case "$f1" in
        right|h) direction=right ;;
        bottom|v) direction=down ;;
        *) die "不正な split 指定: $f1 (right / bottom)" ;;
      esac
      split_args=(pane split "$pane_id" --direction "$direction" --no-focus)
      if [ -n "$f2" ]; then
        ratio="$(split_ratio_args "$f2")"
        [ -n "$ratio" ] && split_args+=(--ratio "$ratio")
      fi
      split="$("$HERDR_BIN" "${split_args[@]}")" || die "pane を分割できませんでした"
      pane_id="$(printf '%s\n' "$split" | jq -r '.result.pane.pane_id // empty')"
      [ -n "$pane_id" ] || die "pane split の応答から ID を取得できませんでした"
      [ -n "$f3" ] && "$HERDR_BIN" pane run "$pane_id" "$f3" >/dev/null
      ;;
  esac
done <<EOF
$records
EOF

"$HERDR_BIN" workspace focus "$workspace_id" >/dev/null
