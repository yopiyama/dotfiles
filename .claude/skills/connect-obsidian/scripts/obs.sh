#!/usr/bin/env bash
# Obsidian vault の定型操作をまとめたラッパー。obsidian CLI を直に叩く代わりにこれを使う。
#
# ノート本文の読み・書き・検索は vault のファイルへ直接アクセスする。CLI は通さない。
# 実際に vault が壊れたため:
#   - CLI は content= を argv で Chromium の process-singleton ソケットに流す。
#     8KB 付近のバッファ境界でマルチバイト文字が分断され、1 文字が U+FFFD 2〜3 個に
#     化ける。数十 KB では Broken pipe でハングし、vault を開いていない
#     二重起動インスタンスが残る。しかも exit 0 なので失敗が見えない
#   - CLI の search / search:context は 1.13.4 では全クエリで空を返す（完全に壊れている）。
#     仮に動いても対象は vault.getMarkdownFiles() だけで、.canvas やファイル名は
#     最初から引っかからない
#
# CLI を使うのは本文を伴わない小さな操作だけ:
#   move / trash（リンク更新が必要）、prop-*（YAML の型付き編集）、open、daily-path
# これらは Obsidian の起動が必要。read / write / append / search / ls は起動不要。
#
# 素の CLI は引数を間違えても黙って別のことをするため、CLI を使う箇所では
# 成功時の定型出力とパスを突き合わせて判定する:
#   - 何があっても常に exit 0。set -e も && も効かない
#   - キー無しの位置引数は黙って無視される
#   - obsidian help（サブコマンド無し）を早期 close パイプに繋ぐとハングする
#
# 使い方: obs.sh <サブコマンド> [引数...]
#
#   read <path>                     ノートを読む (無ければ失敗)
#   read-name <name>                ファイル名で読む (フォルダ・拡張子省略可)
#   exists <path>                   あれば exit 0 / 無ければ exit 1 (出力なし)
#   info <path>                     path/size/更新日時
#   write <path> [src]              作成・上書き。src 省略で stdin。書き込み後に検証
#   append <path> [src]             末尾追記。src 省略で stdin。追記後に検証
#   prepend <path> [src]            先頭追記。src 省略で stdin。追記後に検証
#   ls [folder]                     ファイル一覧 (vault 相対パス・再帰)
#   folders [folder]                フォルダ一覧
#   search [--all] <query> [folder] [limit]
#                                   全文検索。本文とパス名の部分一致 (固定文字列・大小無視)。
#                                   ヒットしたパスの一覧。0 件なら exit 1。
#                                   会話ログ (Conversations) は既定で除外し件数を stderr に出す。
#                                   --all で含める
#   grep [--all] <query> [folder] [limit]
#                                   同じ検索でマッチ行を出す (path:行番号: 行)
#   lint [folder]                   U+FFFD (文字化けの痕跡) を含むノートを列挙
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

# 先頭のコメントブロックがそのまま使い方。行数を数えないので追記しても崩れない
usage() { sed -n '2,/^set -euo pipefail$/p' "$0" | grep '^#' | sed 's/^# \{0,1\}//'; }
die() { echo "obs.sh: $*" >&2; exit 1; }

# mk_tmp が printf -v で入れる。shellcheck が追えないので明示的に宣言しておく
merged=""

TMPFILES=()
cleanup() { [ "${#TMPFILES[@]}" -eq 0 ] || rm -f "${TMPFILES[@]}"; }
trap cleanup EXIT

# 一時ファイルを作って TMPFILES に登録する。呼び出し側は $( ) で包まないこと
# (サブシェルだと TMPFILES への追加が親に残らず後片付けされない)
mk_tmp() {
  # $1: 作ったパスを入れる変数名
  local __t
  __t=$(mktemp)
  TMPFILES+=("$__t")
  printf -v "$1" '%s' "$__t"
}

# --- vault の場所 -----------------------------------------------------------
# Obsidian のレジストリから解決する。CLI (obsidian vault info=path) と違って
# アプリの起動を要求しないため、読み取り・検索はアプリが落ちていても動く。
VAULT=""
resolve_vault() {
  local reg="$HOME/Library/Application Support/obsidian/obsidian.json" p=""
  if [ -f "$reg" ]; then
    # open な vault を優先し、無ければ登録順の先頭
    p=$(jq -r '[.vaults[]? | select(.path)] | (map(select(.open == true)) + .) | .[0].path // empty' "$reg" 2>/dev/null || true)
  fi
  if [ ! -d "${p:-}" ]; then
    p=$(obsidian vault info=path </dev/null 2>&1) || true
  fi
  [ -d "${p:-}" ] || die "vault のパスを解決できません: ${p:-(空)}"
  VAULT=$p
}
vault_path() {
  [ -n "$VAULT" ] || resolve_vault
  printf '%s\n' "$VAULT"
}

# vault 相対パスを絶対パスへ。キー付き引数や vault 外への脱出を弾く
abs_path() {
  local rel=${1:-}
  [ -n "$rel" ] || die "path を指定してください"
  case "$rel" in
    path=*|file=*|name=*) die "path にキー名を含めないでください: $rel" ;;
    /*) die "path は vault ルートからの相対パスで指定してください: $rel" ;;
    ..|../*|*/../*|*/..) die "path に .. は使えません: $rel" ;;
  esac
  printf '%s\n' "$(vault_path)/$rel"
}

# CLI へ生のパスを渡す前の入り口チェック (絶対パスや .. を弾く)
validate_rel() { abs_path "${1:-}" >/dev/null; }

# ドットディレクトリ (.obsidian/.git/.trash) を除いてファイル/ディレクトリを列挙
list_paths() {
  # $1: -type の値 (f|d), $2: 起点となる vault 相対フォルダ (省略で全体)
  local kind=$1 sub=${2:-} root
  root=$(vault_path)
  if [ -n "$sub" ]; then
    [ -d "$root/$sub" ] || die "フォルダが見つかりません: $sub"
  fi
  ( cd "$root" && find "${sub:-.}" -path '*/.*' -prune -o -type "$kind" -print ) \
    | sed 's|^\./||' | grep -vFx "${sub:-.}" | LC_ALL=C sort
}

# --- 本文の書き込み ---------------------------------------------------------
# 同一ディレクトリ内の rename で差し替える。Obsidian の watcher が書きかけの
# 中身を読んでインデックスすることがない。拡張子を変えた一時名にするのは
# 一瞬でも *.md として見えないようにするため。
write_file() {
  # $1: 絶対パス, $2: 内容が入ったローカルファイル, $3: 操作名 (ログ用)
  local abs=$1 src=$2 op=$3 tmp rel
  mkdir -p "$(dirname "$abs")"
  tmp="$abs.obs-tmp.$$"
  TMPFILES+=("$tmp")
  cat "$src" >"$tmp"
  cmp -s "$src" "$tmp" || die "$op の書き込みが途中で壊れました: $abs"
  mv -f "$tmp" "$abs"
  cmp -s "$src" "$abs" || die "$op の検証に失敗しました (書き込み後の内容が一致しません): $abs"
  rel=${abs#"$(vault_path)/"}
  printf '%s: %s (%s bytes)\n' "$op" "$rel" "$(wc -c <"$abs" | tr -d ' ')"
}

# 末尾に改行が無ければ 1 つ足す。既にある空行は保つ。
# コマンド置換は末尾改行を落とすので、最後のバイトが改行なら $(tail -c 1) は空になる
ensure_trailing_nl() {
  local f=$1
  [ -s "$f" ] || return 0
  [ -n "$(tail -c 1 "$f")" ] && printf '\n' >>"$f"
  return 0
}

# stdin またはファイル引数から本文を取り、パスを SRC に入れる。
# $( ) で包まないのは stdin をサブシェルで読ませないためと、一時ファイルを
# TMPFILES に登録して後片付けさせるため
SRC=""
resolve_src() {
  local src=${1:-}
  if [ -n "$src" ]; then
    [ -f "$src" ] || die "本文のファイルが見つかりません: $src"
    SRC=$src
    return 0
  fi
  mk_tmp SRC
  cat >"$SRC"
  [ -s "$SRC" ] || die "本文が空です (ファイルパスを渡すか stdin で流してください)"
}

# --- 検索 -------------------------------------------------------------------
# CLI の search は壊れているので rg で引く。query は固定文字列・大小無視。
# vault は git 管理下にあることがあるので --no-ignore で .gitignore を無視し、
# --hidden を付けないことで .obsidian / .git / .trash を除外する。
require_rg() { command -v rg >/dev/null 2>&1 || die "rg (ripgrep) が必要です"; }

# 会話ログ (ClaudeCode/*/Conversations/) はフックが自動生成する Claude Code の
# セッション記録で、件数が多く同じ語をいくらでも含む。既定では検索対象から外し、
# 何件外したかを stderr に出す (黙って落とすと「検索が漏れた」のと区別できない)。
# --all で含める。
CONV_RE='/Conversations/'
SEARCH_ALL=false
drop_conversations() {
  # stdin をフィルタし、除外件数を stderr に報告する
  local out kept dropped
  out=$(cat)
  [ -n "$out" ] || return 0
  if [ "$SEARCH_ALL" = true ]; then
    printf '%s\n' "$out"
    return 0
  fi
  kept=$(printf '%s\n' "$out" | grep -v "$CONV_RE" || true)
  dropped=$(( $(printf '%s\n' "$out" | grep -c "$CONV_RE" || true) ))
  [ "$dropped" -gt 0 ] && echo "obs.sh: 会話ログ (Conversations) $dropped 件を除外しました (--all で含める)" >&2
  [ -n "$kept" ] && printf '%s\n' "$kept"
  return 0
}

search_paths() {
  # $1: query, $2: folder (空可)。本文マッチとパスマッチの和集合を返す
  local query=$1 folder=${2:-} root
  root=$(vault_path)
  if [ -n "$folder" ]; then
    [ -d "$root/$folder" ] || die "フォルダが見つかりません: $folder"
  fi
  {
    ( cd "$root" && rg --no-ignore --no-messages --files-with-matches \
        --fixed-strings --ignore-case -- "$query" "${folder:-.}" ) || true
    list_paths f "$folder" | rg --fixed-strings --ignore-case -- "$query" || true
  } | sed 's|^\./||' | LC_ALL=C sort -u | drop_conversations
}

# --- CLI 呼び出し (本文を伴わない操作のみ) ----------------------------------
# obsidian は常に exit 0 なので、呼び出し側が CLI_OUT を成功パターンと突き合わせる。
# stdin を飲んでしまうので必ず </dev/null で塞ぐ。
CLI_OUT=""
cli() {
  CLI_OUT=$(obsidian "$@" </dev/null 2>&1) || true
}

# 変更系の呼び出し。Obsidian が再インデックス中などで忙しいと CLI がまれに
# 何も返さず (成否不明のまま) 終わるため、出力が空の間だけリトライする。
cli_mutate() {
  local i
  for i in 1 2 3 4; do
    cli "$@"
    [ -n "$CLI_OUT" ] && return 0
    sleep 0.5
  done
  return 0
}

# 成否は「成功時の定型出力に期待どおりのパスが入っているか」で見る。
# エラー文字列の検出 (blacklist) だとノート本文中の "Error:" を誤検出する。
expect_ok() {
  # $1: 期待する成功プレフィックスの正規表現, $2: 期待するパス, $3: 操作名
  local pattern=$1 want=$2 op=$3
  if [ -z "$CLI_OUT" ]; then
    die "$op に対して obsidian CLI が何も返しませんでした (Obsidian が応答していない可能性があります)"
  fi
  if ! printf '%s' "$CLI_OUT" | grep -qE "^${pattern}"; then
    die "$op が失敗しました: $CLI_OUT"
  fi
  if [ -n "$want" ] && ! printf '%s' "$CLI_OUT" | grep -qF -- "$want"; then
    die "$op の対象パスが要求と違います (要求: $want / CLI: $CLI_OUT)"
  fi
}

cmd=${1:-}
[ -n "$cmd" ] || { usage; exit 1; }
shift || true

# vault の解決は 1 回だけ親シェルで行う。以降の $(vault_path) は VAULT を返すだけ
case "$cmd" in
  -h|--help|help|cli-help) ;;
  *) resolve_vault ;;
esac

case "$cmd" in
  -h|--help) usage ;;
  help|cli-help)
    # サブコマンド無しの help は早期 close パイプでハングするので必ず全部消費する
    if [ -n "${1:-}" ]; then obsidian help "$1" </dev/null | cat; else obsidian help </dev/null | cat; fi
    ;;

  read)
    abs=$(abs_path "${1:-}")
    [ -f "$abs" ] || die "ノートが見つかりません: $1"
    cat "$abs"
    ;;
  read-name)
    name=${1:-}
    [ -n "$name" ] || die "name を指定してください"
    case "$name" in *.*) ;; *) name="$name.md" ;; esac
    hits=()
    while IFS= read -r p; do
      # ${p##*/} は basename。fork せずに末尾要素だけを厳密比較する
      [ "${p##*/}" = "$name" ] && hits+=("$p")
    done < <(list_paths f)
    [ "${#hits[@]}" -gt 0 ] || die "ノートが見つかりません: $name"
    if [ "${#hits[@]}" -gt 1 ]; then
      printf 'obs.sh: 同名のノートが複数あります。read <path> でパスを指定してください:\n' >&2
      printf '  %s\n' "${hits[@]}" >&2
      exit 1
    fi
    cat "$(vault_path)/${hits[0]}"
    ;;
  exists)
    abs=$(abs_path "${1:-}")
    [ -f "$abs" ]
    ;;
  info)
    abs=$(abs_path "${1:-}")
    [ -e "$abs" ] || die "ノートが見つかりません: $1"
    printf 'path: %s\nsize: %s\nmodified: %s\n' \
      "$1" "$(wc -c <"$abs" | tr -d ' ')" "$(date -r "$abs" '+%Y-%m-%d %H:%M:%S')"
    ;;

  write)
    abs=$(abs_path "${1:-}")
    shift || true
    resolve_src "${1:-}"
    write_file "$abs" "$SRC" 書き込み
    ;;

  append|prepend)
    abs=$(abs_path "${1:-}")
    shift || true
    resolve_src "${1:-}"
    mk_tmp merged
    if [ -f "$abs" ]; then
      if [ "$cmd" = append ]; then
        cat "$abs" >"$merged"; ensure_trailing_nl "$merged"; cat "$SRC" >>"$merged"
      else
        cat "$SRC" >"$merged"; ensure_trailing_nl "$merged"; cat "$abs" >>"$merged"
      fi
    else
      cat "$SRC" >"$merged"   # 無ければ新規作成として扱う
    fi
    write_file "$abs" "$merged" "$cmd"
    ;;

  ls)      list_paths f "${1:-}" ;;
  folders) list_paths d "${1:-}" ;;

  search)
    [ "${1:-}" = --all ] && { SEARCH_ALL=true; shift; }
    [ -n "${1:-}" ] || die "検索語を指定してください"
    require_rg
    out=$(search_paths "$1" "${2:-}")
    if [ -z "$out" ]; then
      echo "obs.sh: 一致なし: $1${2:+ (folder=$2)}" >&2
      exit 1
    fi
    if [ -n "${3:-}" ]; then printf '%s\n' "$out" | head -n "$3"; else printf '%s\n' "$out"; fi
    ;;
  grep)
    [ "${1:-}" = --all ] && { SEARCH_ALL=true; shift; }
    [ -n "${1:-}" ] || die "検索語を指定してください"
    require_rg
    root=$(vault_path)
    if [ -n "${2:-}" ]; then
      [ -d "$root/$2" ] || die "フォルダが見つかりません: $2"
    fi
    out=$( cd "$root" && rg --no-ignore --no-messages --with-filename --line-number \
             --fixed-strings --ignore-case -- "$1" "${2:-.}" | sed 's|^\./||' \
             | drop_conversations ) || true
    if [ -z "$out" ]; then
      # 本文には無くてもパス名に一致することがあるので、そちらを案内する
      names=$(search_paths "$1" "${2:-}")
      if [ -n "$names" ]; then
        echo "obs.sh: 本文一致なし。パス名のみ一致:" >&2
        printf '%s\n' "$names"
        exit 0
      fi
      echo "obs.sh: 一致なし: $1${2:+ (folder=$2)}" >&2
      exit 1
    fi
    if [ -n "${3:-}" ]; then printf '%s\n' "$out" | head -n "$3"; else printf '%s\n' "$out"; fi
    ;;
  lint)
    require_rg
    root=$(vault_path)
    if [ -n "${1:-}" ]; then
      [ -d "$root/$1" ] || die "フォルダが見つかりません: $1"
    fi
    # U+FFFD は content= 経由の書き込みで文字が分断された痕跡。
    # 会話ログは「化けた文字の話をしている」ログが引っかかるだけなので除外する
    out=$( cd "$root" && rg --no-ignore --no-messages --with-filename --line-number \
             --fixed-strings -- $'\xef\xbf\xbd' "${1:-.}" | sed 's|^\./||' \
             | drop_conversations ) || true
    if [ -z "$out" ]; then
      echo "文字化け (U+FFFD) は見つかりませんでした"
    else
      printf '%s\n' "$out"
    fi
    ;;

  frontmatter)
    abs=$(abs_path "${1:-}")
    [ -f "$abs" ] || die "ノートが見つかりません: $1"
    awk 'NR==1 && $0 != "---" { exit } NR==1 { next } /^---[[:space:]]*$/ { exit } { print }' "$abs"
    ;;
  prop-get)
    validate_rel "${1:-}"
    [ -n "${2:-}" ] || die "プロパティ名を指定してください"
    cli property:read "name=$2" "path=$1"
    case "$CLI_OUT" in Error:*) exit 1 ;; esac
    printf '%s\n' "$CLI_OUT"
    ;;
  prop-set)
    validate_rel "${1:-}"
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
    validate_rel "${1:-}"
    [ -n "${2:-}" ] || die "プロパティ名を指定してください"
    cli_mutate property:remove "name=$2" "path=$1"
    # 元から無かった場合も削除済みとして扱う (冪等)
    if ! printf '%s' "$CLI_OUT" | grep -qE '^(Removed: |Error: Property )'; then
      die "プロパティ削除 が失敗しました: $CLI_OUT"
    fi
    printf '%s\n' "$CLI_OUT"
    ;;

  move)
    validate_rel "${1:-}"
    [ -n "${2:-}" ] || die "移動先を指定してください"
    cli_mutate move "path=$1" "to=$2"
    expect_ok "Moved: " "$2" 移動
    printf '%s\n' "$CLI_OUT"
    ;;
  trash)
    validate_rel "${1:-}"
    cli_mutate delete "path=$1"
    expect_ok "Moved to trash: " "$1" 削除
    printf '%s\n' "$CLI_OUT"
    ;;

  open)
    validate_rel "${1:-}"
    args=(open "path=$1")
    [ "${2:-}" = newtab ] && args+=(newtab)
    cli "${args[@]}"
    printf '%s\n' "$CLI_OUT"
    ;;

  daily-path)
    cli daily:path
    [ -n "$CLI_OUT" ] || die "デイリーノートのパスを取得できませんでした (Obsidian は起動していますか?)"
    printf '%s\n' "$CLI_OUT"
    ;;
  daily-read)
    cli daily:path
    [ -n "$CLI_OUT" ] || die "デイリーノートのパスを取得できませんでした (Obsidian は起動していますか?)"
    abs="$(vault_path)/$CLI_OUT"
    [ -f "$abs" ] || die "デイリーノートがまだありません: $CLI_OUT"
    cat "$abs"
    ;;
  daily-append)
    resolve_src "${1:-}"
    cli daily:path
    [ -n "$CLI_OUT" ] || die "デイリーノートのパスを取得できませんでした (Obsidian は起動していますか?)"
    rel=$CLI_OUT
    abs="$(vault_path)/$rel"
    if [ ! -f "$abs" ]; then
      # テンプレート (daily-notes の template 設定) を効かせたいので、
      # 実体の作成だけは Obsidian に任せる。本文は下でファイルに直接追記する
      cli daily
      for _ in 1 2 3 4 5; do
        [ -f "$abs" ] && break
        sleep 0.4
      done
    fi
    mk_tmp merged
    if [ -f "$abs" ]; then
      cat "$abs" >"$merged"; ensure_trailing_nl "$merged"; cat "$SRC" >>"$merged"
    else
      cat "$SRC" >"$merged"
    fi
    write_file "$abs" "$merged" デイリーノート追記
    ;;

  vault-path) vault_path ;;

  *) die "不明なサブコマンド: $cmd (obs.sh --help でサブコマンド一覧)" ;;
esac
