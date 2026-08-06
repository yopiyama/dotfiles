#!/usr/bin/env bash
# pr-comments スキルの Obsidian タスクノート (親 + 子 2 層) を操作する。
#
# 保存先の構造:
#   ClaudeCode/<project>/Tasks/PR-<pr>.md    親: PR 情報 + Bases ステータスビュー
#   ClaudeCode/<project>/Tasks/PR-<pr>/      子: 1 スレッド = 1 ノート
#     01_<短い要約>.md, 02_<短い要約>.md, ...
#
# パス組み立て・連番採番・frontmatter の突き合わせ・ステータス文字列といった
# 定型部分をここに閉じ込める。ノート本文 (指摘コメント全文・補足・回答案) の
# 執筆だけが Claude の仕事。書き込みは obs.sh 経由なので必ず検証される。
#
# 使い方: pr-task-notes.sh <サブコマンド> [引数...]
#
#   共通オプション: --project <name>  省略時はカレントリポジトリ名。
#                                     PR のリポジトリ名を明示するのが望ましい
#
#   init <pr> --url <PR URL> --repo <owner/name> [--title <t>] [--scope <s>]
#           親ノートを作成・更新する (Bases ビューは毎回この定型で上書き)
#   list <pr>
#           子ノートを TSV で列挙: index / path / comment_url / status / memo
#           更新時の突き合わせはこの comment_url をキーに行う
#   next-index <pr>
#           次に振るゼロ埋め 2 桁の連番
#   path-for <pr> <index>
#           その連番の既存子ノートのパス (無ければ exit 1)。
#           再実行時にファイル名を変えないための解決に使う
#   read <pr> <index>
#           子ノートを読む (マージ前に必ずこれで現状を取る)
#   put <pr> <index> <slug> [src]
#           子ノートを作成・上書き。src 省略で stdin。
#           その連番の既存ノートがあれば slug を無視して既存ファイル名を維持する
#   set-status <pr> <index> <status> [memo]
#           status / memo / updated を frontmatter に設定する。
#           status は下記のキーか絵文字込みの正式文字列のみ受け付ける:
#             ready=🟢 着手可能  waiting=🟡 返信待ち  local=🔵 手元では対応済み
#             hold=⏸️ 保留       done=✅ 完了
#   folder <pr>
#           子ノートフォルダの vault 相対パス
#   parent-path <pr>
#           親ノートの vault 相対パス
#   open <pr>
#           親ノートを Obsidian で開く
set -euo pipefail

OBS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../connect-obsidian/scripts" && pwd)/obs.sh"

usage() { sed -n '2,48p' "$0" | sed 's/^# \{0,1\}//'; }
die() { echo "pr-task-notes.sh: $*" >&2; exit 1; }

PROJECT="" URL="" REPO="" TITLE="" SCOPE=""
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT=$2; shift 2 ;;
    --url) URL=$2; shift 2 ;;
    --repo) REPO=$2; shift 2 ;;
    --title) TITLE=$2; shift 2 ;;
    --scope) SCOPE=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) die "不明なオプション: $1" ;;
    *) ARGS+=("$1"); shift ;;
  esac
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

cmd=${1:-}
[ -n "$cmd" ] || { usage; exit 1; }
shift || true

if [ -z "$PROJECT" ]; then
  PROJECT=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || true)" 2>/dev/null || true)
  [ -n "$PROJECT" ] && [ "$PROJECT" != "/" ] || die "--project を指定してください (git リポジトリ外です)"
fi

# 検証つきの引数パースは値を返さずグローバルへ入れる。$(...) の中で die しても
# サブシェルしか死なず、呼び出し側が空文字のまま進んでしまうため。
PR="" IDX=""
parse_pr() {
  local pr=${1:-}
  [ -n "$pr" ] || die "PR 番号を指定してください"
  # "#123" や URL を渡されても番号だけ取り出す
  pr=${pr##*/}; pr=${pr#\#}
  case "$pr" in
    ''|*[!0-9]*) die "PR 番号が数値ではありません: ${1:-}" ;;
  esac
  PR=$pr
}

parse_idx() {
  local i=${1:-}
  [ -n "$i" ] || die "連番 (index) を指定してください"
  case "$i" in
    ''|*[!0-9]*) die "連番が数値ではありません: $i" ;;
  esac
  IDX=$(printf '%02d' "$((10#$i))")
}

base_dir()    { printf 'ClaudeCode/%s/Tasks\n' "$PROJECT"; }
child_dir()   { printf '%s/PR-%s\n' "$(base_dir)" "$1"; }
parent_path() { printf '%s/PR-%s.md\n' "$(base_dir)" "$1"; }

# 子ノートのパスを配列 CHILDREN へ列挙する。obs.sh ls はフォルダが無ければ
# エラーで落ちるが、ここでは stderr を捨てて空配列に倒すので未作成でも自然に動く。
# ループ内で obs.sh を呼ぶ都合上、一覧は必ず先に配列へ確定させてから回す
# (while read のループ内で obsidian を呼ぶと stdin を飲まれて 1 件目で終わる)
CHILDREN=()
load_children() {
  local line
  CHILDREN=()
  while IFS= read -r line; do
    [ -n "$line" ] && CHILDREN+=("$line")
  done < <("$OBS" ls "$(child_dir "$1")" 2>/dev/null | grep -E '/[0-9]{2}_[^/]*\.md$' | sort || true)
  return 0   # ループ最後の判定結果を set -e に漏らさない
}

STATUS=""
parse_status() {
  case "$1" in
    ready)   STATUS='🟢 着手可能' ;;
    waiting) STATUS='🟡 返信待ち' ;;
    local)   STATUS='🔵 手元では対応済み' ;;
    hold)    STATUS='⏸️ 保留' ;;
    done)    STATUS='✅ 完了' ;;
    '🟢 着手可能'|'🟡 返信待ち'|'🔵 手元では対応済み'|'⏸️ 保留'|'✅ 完了') STATUS=$1 ;;
    *) die "status は ready/waiting/local/hold/done か正式文字列のみです: $1" ;;
  esac
}

# 連番に対応する既存子ノートのパスを CHILD へ入れる (無ければ空)
CHILD=""
find_child() {
  local c
  CHILD=""
  load_children "$1"
  for c in ${CHILDREN[@]+"${CHILDREN[@]}"}; do
    case "$c" in */"$2"_*.md) CHILD=$c; return 0 ;; esac
  done
  return 0   # 見つからない場合も CHILD が空になるだけで、それ自体はエラーではない
}

case "$cmd" in
  folder)      parse_pr "${1:-}"; child_dir "$PR" ;;
  parent-path) parse_pr "${1:-}"; parent_path "$PR" ;;

  init)
    parse_pr "${1:-}"; pr=$PR
    [ -n "$URL" ] || die "--url に PR の URL を指定してください"
    [ -n "$REPO" ] || die "--repo に owner/name を指定してください"
    body=$(mktemp)
    {
      printf -- '---\n'
      printf 'pr: %s\n' "$URL"
      printf 'repo: %s\n' "$REPO"
      printf 'updated: %s\n' "$(date +%F)"
      printf -- '---\n\n'
      printf '# PR #%s レビュー対応タスク\n\n' "$pr"
      printf 'PR: %s\n' "$URL"
      [ -n "$TITLE" ] && printf 'タイトル: %s\n' "$TITLE"
      [ -n "$SCOPE" ] && printf '対象: %s\n' "$SCOPE"
      printf '\n## ステータス\n\n'
      printf '```base\n'
      printf 'filters:\n  and:\n    - file.inFolder("%s")\n' "$(child_dir "$pr")"
      printf 'views:\n'
      printf '  - type: table\n    name: タスク一覧\n'
      printf '    groupBy:\n      property: status\n      direction: DESC\n'
      printf '    order:\n      - file.name\n      - memo\n      - priority\n      - author\n      - location\n'
      printf '    sort:\n      - property: file.name\n        direction: ASC\n'
      printf '```\n'
    } >"$body"
    "$OBS" write "$(parent_path "$pr")" "$body"
    rm -f "$body"
    ;;

  list)
    parse_pr "${1:-}"; pr=$PR
    load_children "$pr"
    printf 'index\tpath\tcomment_url\tstatus\tmemo\n'
    for p in ${CHILDREN[@]+"${CHILDREN[@]}"}; do
      idx=$(basename "$p"); idx=${idx%%_*}
      url=$("$OBS" prop-get "$p" comment_url 2>/dev/null || true)
      st=$("$OBS" prop-get "$p" status 2>/dev/null || true)
      memo=$("$OBS" prop-get "$p" memo 2>/dev/null || true)
      printf '%s\t%s\t%s\t%s\t%s\n' "$idx" "$p" "$url" "$st" "$memo"
    done
    ;;

  next-index)
    parse_pr "${1:-}"; pr=$PR
    load_children "$pr"
    last=0
    for p in ${CHILDREN[@]+"${CHILDREN[@]}"}; do
      n=$(basename "$p"); n=${n%%_*}
      n=$((10#$n))
      [ "$n" -gt "$last" ] && last=$n
    done
    printf '%02d\n' "$((last + 1))"
    ;;

  path-for)
    parse_pr "${1:-}"; parse_idx "${2:-}"
    find_child "$PR" "$IDX"
    [ -n "$CHILD" ] || exit 1
    printf '%s\n' "$CHILD"
    ;;

  read)
    parse_pr "${1:-}"; parse_idx "${2:-}"
    find_child "$PR" "$IDX"
    [ -n "$CHILD" ] || die "連番 $IDX の子ノートがありません (PR-$PR)"
    "$OBS" read "$CHILD"
    ;;

  put)
    parse_pr "${1:-}"; parse_idx "${2:-}"
    slug=${3:-}
    [ -n "$slug" ] || die "slug (短い要約) を指定してください"
    case "$slug" in */*) die "slug にスラッシュは使えません: $slug" ;; esac
    # 本文の取り込みを最優先で済ませる。obsidian CLI は stdin を飲んでしまうので、
    # 先に既存ノートを探すと stdin 経由の本文が消える
    src=${4:-}
    tmp=""
    if [ -z "$src" ]; then
      tmp=$(mktemp); cat >"$tmp"; src=$tmp
    elif [ ! -f "$src" ]; then
      # slug をクォートし忘れて単語分割された場合もここに来る
      die "本文のファイルが見つかりません: $src (slug に空白を含む場合はクォートしてください)"
    fi
    [ -s "$src" ] || die "本文が空です (ファイルパスを渡すか stdin で流してください)"
    [ $# -le 4 ] || die "引数が多すぎます (slug に空白を含む場合はクォートしてください): $*"
    # 既存ノートがあればファイル名は変えない (リンクを壊さないため)
    find_child "$PR" "$IDX"
    target=$CHILD
    if [ -z "$target" ]; then
      target="$(child_dir "$PR")/${IDX}_${slug}.md"
    fi
    "$OBS" write "$target" "$src"
    [ -n "$tmp" ] && rm -f "$tmp"
    ;;

  set-status)
    parse_pr "${1:-}"; parse_idx "${2:-}"
    [ -n "${3:-}" ] || die "status を指定してください"
    parse_status "$3"
    find_child "$PR" "$IDX"
    [ -n "$CHILD" ] || die "連番 $IDX の子ノートがありません (PR-$PR)"
    "$OBS" prop-set "$CHILD" status "$STATUS"
    [ -n "${4:-}" ] && "$OBS" prop-set "$CHILD" memo "$4"
    "$OBS" prop-set "$CHILD" updated "$(date +%F)" date
    ;;

  open)
    parse_pr "${1:-}"
    "$OBS" open "$(parent_path "$PR")"
    ;;

  *) die "不明なサブコマンド: $cmd (pr-task-notes.sh --help でサブコマンド一覧)" ;;
esac
