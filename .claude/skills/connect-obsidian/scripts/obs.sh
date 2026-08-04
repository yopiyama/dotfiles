#!/usr/bin/env bash
# Obsidian vault の定型操作をまとめたラッパー。obsidian CLI を直に叩く代わりにこれを使う。
#
# 素の obsidian CLI は「引数を間違えても黙って別のことをする」ため事故が多い:
#   - 何があっても常に exit 0。set -e も && も効かない
#   - キー無しの位置引数は無視される。obsidian read foo.md は foo.md ではなく
#     アクティブファイルを読み、obsidian create foo.md content=... は
#     vault ルートに Untitled.md を作る
#   - overwrite を付け忘れると上書きではなく "note 1.md" という別ファイルができる
#   - content= の中のリテラル \n / \t は無条件に実改行・タブへ変換される
#   - obsidian help (サブコマンド無し) を head などの早期 close パイプに繋ぐとハングする
#
# このスクリプトは path=/name= のキー付けを強制し、成功時の出力パターンを
# 突き合わせ、書き込み後は read で読み直して内容一致を検証する。CLI 経由で
# 内容が化けた場合は vault のファイルへ直接書いて再検証する。
#
# 使い方: obs.sh <サブコマンド> [引数...]
#
#   read <path>                     ノートを読む (無ければ失敗)
#   read-name <name>                ファイル名で読む (フォルダ・拡張子省略可)
#   exists <path>                   あれば exit 0 / 無ければ exit 1 (出力なし)
#   info <path>                     path/size/更新日時などのメタデータ
#   write <path> [src]              作成・上書き。src 省略で stdin。書き込み後に検証
#   append <path> [src]             末尾追記。src 省略で stdin。追記後に検証
#   prepend <path> [src]            先頭追記。src 省略で stdin。追記後に検証
#   ls [folder]                     ファイル一覧
#   folders [folder]                フォルダ一覧
#   search <query> [folder] [limit] 全文検索 (ヒットしたパスの一覧)
#   grep <query> [folder] [limit]   全文検索 (マッチ行のコンテキスト付き)
#   frontmatter <path>              frontmatter を YAML で出力
#   prop-get <path> <name>          プロパティ読み取り (無ければ空文字で exit 1)
#   prop-set <path> <name> <value> [type]  プロパティ設定 (設定後に読み直して検証)
#   prop-del <path> <name>          プロパティ削除
#   move <path> <to>                移動・リネーム
#   trash <path>                    ゴミ箱へ移動 (permanent は扱わない)
#   open <path> [newtab]            Obsidian で開く
#   daily-path                      デイリーノートのパス
#   daily-read                      デイリーノートを読む
#   daily-append [src]              デイリーノートに追記。src 省略で stdin
#   vault-path                      vault のルートパス
#   help [subcommand]               obsidian CLI のヘルプ (ハングしない形で出す)
set -euo pipefail

usage() { sed -n '2,47p' "$0" | sed 's/^# \{0,1\}//'; }
die() { echo "obs.sh: $*" >&2; exit 1; }

# obsidian CLI を叩いて出力を CLI_OUT に入れる。CLI は常に exit 0 なので
# 呼び出し側が CLI_OUT を成功パターンと突き合わせて判定する。
# obsidian は stdin を飲んでしまうので必ず </dev/null で塞ぐ。塞がないと
# while read のループ内やパイプの受け側で呼んだとき、残りの入力が消える。
CLI_OUT=""
cli() {
  CLI_OUT=$(obsidian "$@" </dev/null 2>&1) || true
}

# 変更系の呼び出し。Obsidian が再インデックス中などで忙しいと CLI がまれに
# 何も返さず (成否不明のまま) 終わるため、出力が空の間だけリトライする。
# 一覧・検索は空が正常な結果なので、こちらは変更系専用。
cli_mutate() {
  local i
  for i in 1 2 3 4; do
    cli "$@"
    [ -n "$CLI_OUT" ] && return 0
    sleep 0.5
  done
  return 0
}

# 変更系コマンドの成否は「成功時の定型出力に期待どおりのパスが入っているか」で見る。
# エラー文字列の検出 (blacklist) だとノート本文中の "Error:" を誤検出するため、
# 成功パターンの whitelist で判定する。
expect_ok() {
  # $1: 期待する成功プレフィックスの正規表現, $2: 期待するパス, $3: 操作名
  local pattern=$1 want=$2 op=$3
  if [ -z "$CLI_OUT" ]; then
    die "$op に対して obsidian CLI が何も返しませんでした (Obsidian が応答していない可能性があります)"
  fi
  if ! printf '%s' "$CLI_OUT" | grep -qE "^${pattern}"; then
    die "$op が失敗しました: $CLI_OUT"
  fi
  # overwrite 忘れによる "note 1.md" 生成や Untitled.md 事故を検出する
  if [ -n "$want" ] && ! printf '%s' "$CLI_OUT" | grep -qF -- "$want"; then
    die "$op の対象パスが要求と違います (要求: $want / CLI: $CLI_OUT)"
  fi
}

require_path() {
  # 引数に key= が付いたパスを渡す事故 (path=path=... になる) を先に弾く
  [ -n "${1:-}" ] || die "path を指定してください"
  case "$1" in
    path=*|file=*|name=*) die "path にキー名を含めないでください: $1" ;;
  esac
}

vault_path() {
  local p
  p=$(obsidian vault info=path </dev/null 2>&1) || true
  [ -d "$p" ] || die "vault のパスを解決できません (Obsidian は起動していますか?): $p"
  printf '%s\n' "$p"
}

# 末尾の改行だけを落として比較する。obsidian read は常に末尾へ改行を 1 つ足し、
# content="$(cat f)" 側はコマンド置換で末尾改行が落ちるため、そのままでは必ずずれる。
strip_trailing_nl() { printf '%s' "$(cat "$1")"; }

# 期待内容と一致するまで read を数回リトライして $2 に落とす。
# vault へ直接書いた直後は Obsidian のインデックス反映に一瞬かかり、
# read が空を返すことがあるため待ちを入れる。
read_until_match() {
  # $1: vault 相対パス, $2: 出力先ファイル, $3: 期待内容のファイル
  local target=$1 out=$2 want=$3 i
  for i in 1 2 3 4 5; do
    obsidian read "path=$target" >"$out" </dev/null 2>&1 || true
    [ "$(strip_trailing_nl "$want")" = "$(strip_trailing_nl "$out")" ] && return 0
    sleep 0.4
  done
  return 1
}

# obsidian file でメタデータが引けるか (= ノートが存在するか) を見る。
# 空応答は忙しいだけの可能性があるのでリトライする
file_meta() {
  # $1: "path=..." または "file=..."
  local i
  for i in 1 2 3 4; do
    cli file "$1"
    [ -n "$CLI_OUT" ] && break
    sleep 0.5
  done
  printf '%s' "$CLI_OUT" | grep -qE '^path\b'
}

read_note() {
  # 存在確認を file で先に済ませてから読む。read は not found でも exit 0 で
  # エラー文を本文のように返すため、read 自体では成否を判定できない
  require_path "$1"
  file_meta "path=$1" || die "ノートが読めません: ${CLI_OUT:-(応答なし)}"
  obsidian read "path=$1" </dev/null
}

# 内容の書き込みは CLI (content=) を先に試し、read で読み直して一致しなければ
# vault のファイルへ直接書いて再検証する。リテラル \n / \t を含む本文は
# CLI では表現できないので、その場合は必然的に直接書き込みになる。
write_verified() {
  # $1: vault からの相対パス, $2: 内容が入ったローカルファイル, $3: 操作名 (ログ用)
  local target=$1 src=$2 op=$3 vroot back
  back=$(mktemp)
  trap 'rm -f "$back"' RETURN

  cli_mutate create "path=$target" "content=$(cat "$src")" overwrite
  expect_ok 'Created: |Overwrote: ' "$target" "$op"

  if read_until_match "$target" "$back" "$src"; then
    printf '%s: %s (CLI)\n' "$op" "$target"
    return 0
  fi

  # CLI の \n / \t 変換で化けた。vault へ直接書いて実バイトを合わせる
  vroot=$(vault_path)
  mkdir -p "$vroot/$(dirname "$target")"
  cat "$src" >"$vroot/$target"
  if ! read_until_match "$target" "$back" "$src"; then
    die "$op の検証に失敗しました (直接書き込み後も内容が一致しません): $target"
  fi
  printf '%s: %s (直接書き込み: 本文にリテラル \\n / \\t を含むため)\n' "$op" "$target"
}

# stdin またはファイル引数から本文を取り、一時ファイルのパスを返す
content_src() {
  local src=${1:-} tmp
  if [ -n "$src" ]; then
    [ -f "$src" ] || die "本文のファイルが見つかりません: $src"
    printf '%s\n' "$src"
    return 0
  fi
  tmp=$(mktemp)
  cat >"$tmp"
  [ -s "$tmp" ] || die "本文が空です (ファイルパスを渡すか stdin で流してください)"
  printf '%s\n' "$tmp"
}

cmd=${1:-}
[ -n "$cmd" ] || { usage; exit 1; }
shift || true

case "$cmd" in
  -h|--help) usage ;;
  help|cli-help)
    # サブコマンド無しの help は早期 close パイプでハングするので必ず全部消費する
    if [ -n "${1:-}" ]; then obsidian help "$1" </dev/null | cat; else obsidian help </dev/null | cat; fi
    ;;

  read)      read_note "${1:-}" ;;
  read-name)
    [ -n "${1:-}" ] || die "name を指定してください"
    file_meta "file=$1" || die "ノートが読めません: ${CLI_OUT:-(応答なし)}"
    obsidian read "file=$1" </dev/null
    ;;
  exists)
    require_path "${1:-}"
    file_meta "path=$1"
    ;;
  info)
    require_path "${1:-}"
    file_meta "path=$1" || die "ノートが見つかりません: ${CLI_OUT:-(応答なし)}"
    printf '%s\n' "$CLI_OUT"
    ;;

  write)
    require_path "${1:-}"
    target=$1; shift || true
    write_verified "$target" "$(content_src "${1:-}")" 書き込み
    ;;

  append|prepend)
    require_path "${1:-}"
    target=$1; shift || true
    src=$(content_src "${1:-}")
    # 追記系も検証したいが差分位置の判定が面倒なので、read で現状を取って
    # ローカルで連結し、write_verified で丸ごと書き直す。CLI の append は
    # \n 変換の検証ができないため使わない
    merged=$(mktemp)
    if file_meta "path=$target"; then
      cur=$(mktemp)
      obsidian read "path=$target" >"$cur" </dev/null 2>&1 || true
      if [ "$cmd" = append ]; then
        { strip_trailing_nl "$cur"; printf '\n'; cat "$src"; } >"$merged"
      else
        { strip_trailing_nl "$src"; printf '\n'; cat "$cur"; } >"$merged"
      fi
      rm -f "$cur"
    else
      cat "$src" >"$merged"   # 無ければ新規作成として扱う
    fi
    write_verified "$target" "$merged" "$cmd"
    rm -f "$merged"
    ;;

  ls)
    if [ -n "${1:-}" ]; then cli files "folder=$1"; else cli files; fi
    printf '%s\n' "$CLI_OUT"
    ;;
  folders)
    if [ -n "${1:-}" ]; then cli folders "folder=$1"; else cli folders; fi
    printf '%s\n' "$CLI_OUT"
    ;;

  search|grep)
    [ -n "${1:-}" ] || die "検索語を指定してください"
    sub=search; [ "$cmd" = grep ] && sub=search:context
    args=("$sub" "query=$1")
    [ -n "${2:-}" ] && args+=("path=$2")
    [ -n "${3:-}" ] && args+=("limit=$3")
    cli "${args[@]}"
    printf '%s\n' "$CLI_OUT"
    ;;

  frontmatter)
    require_path "${1:-}"
    cli properties "path=$1"
    printf '%s\n' "$CLI_OUT"
    ;;
  prop-get)
    require_path "${1:-}"
    [ -n "${2:-}" ] || die "プロパティ名を指定してください"
    cli property:read "name=$2" "path=$1"
    case "$CLI_OUT" in Error:*) exit 1 ;; esac
    printf '%s\n' "$CLI_OUT"
    ;;
  prop-set)
    require_path "${1:-}"
    [ -n "${2:-}" ] || die "プロパティ名を指定してください"
    [ $# -ge 3 ] || die "値を指定してください"
    args=(property:set "name=$2" "value=$3" "path=$1")
    [ -n "${4:-}" ] && args+=("type=$4")
    cli_mutate "${args[@]}"
    expect_ok "Set " "" "プロパティ設定"
    cli property:read "name=$2" "path=$1"
    [ "$CLI_OUT" = "$3" ] || die "プロパティ設定の検証に失敗しました (設定: $3 / 読み取り: $CLI_OUT)"
    printf 'set %s: %s (%s)\n' "$2" "$3" "$1"
    ;;
  prop-del)
    require_path "${1:-}"
    [ -n "${2:-}" ] || die "プロパティ名を指定してください"
    cli_mutate property:remove "name=$2" "path=$1"
    # 元から無かった場合も削除済みとして扱う (冪等)
    if ! printf '%s' "$CLI_OUT" | grep -qE '^(Removed: |Error: Property )'; then
      die "プロパティ削除 が失敗しました: $CLI_OUT"
    fi
    printf '%s\n' "$CLI_OUT"
    ;;

  move)
    require_path "${1:-}"
    [ -n "${2:-}" ] || die "移動先を指定してください"
    cli_mutate move "path=$1" "to=$2"
    expect_ok "Moved: " "$2" 移動
    printf '%s\n' "$CLI_OUT"
    ;;
  trash)
    require_path "${1:-}"
    cli_mutate delete "path=$1"
    expect_ok "Moved to trash: " "$1" 削除
    printf '%s\n' "$CLI_OUT"
    ;;

  open)
    require_path "${1:-}"
    args=(open "path=$1")
    [ "${2:-}" = newtab ] && args+=(newtab)
    cli "${args[@]}"
    printf '%s\n' "$CLI_OUT"
    ;;

  daily-path) cli daily:path; printf '%s\n' "$CLI_OUT" ;;
  daily-read) obsidian daily:read </dev/null ;;
  daily-append)
    src=$(content_src "${1:-}")
    cli_mutate daily:append "content=$(cat "$src")"
    expect_ok "Appended" "" デイリーノート追記
    printf '%s\n' "$CLI_OUT"
    ;;

  vault-path) vault_path ;;

  *) die "不明なサブコマンド: $cmd (obs.sh --help でサブコマンド一覧)" ;;
esac
