#!/usr/bin/env bash
#
# dotfiles 側の共有 Codex 設定を ~/.codex/config.toml に同期する。
#
# config.shared.toml に定義したトップレベルの単一行 TOML 値と table を正として
# 上書きする。Codex Desktop が管理する
# project trust、UI 状態、plugins、共有対象外の MCP とその認証情報は保持する。
# TOML 全体を置換しないため、端末固有の自動生成設定は壊さない。
#
#   scripts/sync-codex-config.sh
#   scripts/sync-codex-config.sh --dry-run
#
# テスト等では --source / --target で対象を差し替えられる。
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$REPO/.codex/config.shared.toml"
TARGET="$HOME/.codex/config.toml"
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: sync-codex-config.sh [--dry-run] [--source PATH] [--target PATH]

Synchronize top-level, single-line TOML assignments and tables from the source
file into the target Codex config. Managed source values and tables are
authoritative; every other target setting is preserved.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      ;;
    --source)
      [ "$#" -ge 2 ] || { echo "--source にはパスが必要です" >&2; exit 2; }
      SOURCE="$2"
      shift
      ;;
    --target)
      [ "$#" -ge 2 ] || { echo "--target にはパスが必要です" >&2; exit 2; }
      TARGET="$2"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "不明な引数: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

[ -f "$SOURCE" ] || { echo "共有設定が見つかりません: $SOURCE" >&2; exit 1; }
[ ! -L "$TARGET" ] || {
  echo "同期先が symlink です。config.toml は実ファイルとして保持してください: $TARGET" >&2
  exit 1
}

# 管理用ソースは、トップレベルの単一行 key = value と通常の table（その子 table を
# 含む）だけを受け付ける。これにより任意の TOML を雑に書き換えず、同期範囲を明示的
# に保つ。MCP は他の server を巻き込まないよう [mcp_servers.<name>] 単位で管理する。
MANAGED_VALUES="$(mktemp "${TMPDIR:-/tmp}/codex-managed-values.XXXXXX")"
MANAGED_TABLES="$(mktemp "${TMPDIR:-/tmp}/codex-managed-tables.XXXXXX")"
MANAGED_TABLE_ROOTS="$(mktemp "${TMPDIR:-/tmp}/codex-managed-table-roots.XXXXXX")"
cleanup() {
  rm -f "$MANAGED_VALUES" "$MANAGED_TABLES" "$MANAGED_TABLE_ROOTS" \
    "${WITHOUT_MANAGED_TABLES:-}" "${WORK_FILE:-}"
}
trap cleanup EXIT HUP INT TERM

awk -v managed_tables="$MANAGED_TABLES" -v managed_table_roots="$MANAGED_TABLE_ROOTS" '
  function invalid(message) {
    print message > "/dev/stderr"
    exit 2
  }
  /^[[:space:]]*($|#)/ {
    if (in_table) print $0 >> managed_tables
    next
  }
  /^[[:space:]]*\[/ {
    line = $0
    sub(/^[[:space:]]*/, "", line)
    if (line !~ /^\[[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)*\][[:space:]]*(#.*)?$/) {
      invalid("config.shared.toml の table 名が不正です: " $0)
    }
    in_table = 1
    table = line
    sub(/^\[/, "", table)
    sub(/\].*$/, "", table)
    split(table, parts, /\./)
    if (parts[1] == "mcp_servers") {
      if (table !~ /^mcp_servers\./) {
        invalid("config.shared.toml の MCP table は [mcp_servers.<name>] 形式が必要です: " $0)
      }
      table_root = "mcp_servers." parts[2]
    } else {
      table_root = parts[1]
    }
    if (!seen_table_root[table_root]++) print table_root >> managed_table_roots
    print $0 >> managed_tables
    next
  }
  {
    if (in_table) {
      print $0 >> managed_tables
      next
    }
    line = $0
    sub(/^[[:space:]]*/, "", line)
    if (line !~ /^[A-Za-z0-9_-]+[[:space:]]*=/) {
      invalid("config.shared.toml の形式が不正です: " $0)
    }
    key = line
    sub(/[[:space:]]*=.*/, "", key)
    if (seen[key]++) {
      invalid("config.shared.toml に重複したキーがあります: " key)
    }
    value = line
    sub(/^[A-Za-z0-9_-]+[[:space:]]*=[[:space:]]*/, "", value)
    print key "\t" key " = " value
  }
' "$SOURCE" >"$MANAGED_VALUES"

[ -s "$MANAGED_VALUES" ] || [ -s "$MANAGED_TABLES" ] || {
  echo "共有設定に同期対象がありません: $SOURCE" >&2
  exit 1
}

if [ -e "$TARGET" ]; then
  TARGET_INPUT="$TARGET"
else
  TARGET_INPUT="/dev/null"
fi

TARGET_DIR="$(dirname "$TARGET")"
if [ "$DRY_RUN" -eq 0 ]; then
  mkdir -p "$TARGET_DIR"
fi
WORK_FILE="$(mktemp "${TMPDIR:-/tmp}/codex-config-sync.XXXXXX")"

# 最初の TOML table header より前だけをトップレベルとして扱う。source にあるキーを
# 置換し、存在しないキーは最初の table header の直前（または EOF）に追加する。
awk -v root_values="$MANAGED_VALUES" -F '\t' '
  FILENAME == root_values {
    order[++count] = $1
    value[$1] = $2
    next
  }
  function emit_root(before_table,  i, key, missing, last_content) {
    if (root_emitted) return
    for (i = 1; i <= count; i++) {
      key = order[i]
      if (!(key in present)) missing++
    }

    # 未指定キーを追加する場合だけ、既存 root 部の末尾空行を取り除く。追加値と
    # table の間には空行を一つ置き、既存の端末設定の書式を崩さない。
    last_content = root_count
    if (missing) {
      while (last_content > 0 && root[last_content] ~ /^[[:space:]]*$/) last_content--
    }
    for (i = 1; i <= (missing ? last_content : root_count); i++) print root[i]
    for (i = 1; i <= count; i++) {
      key = order[i]
      if (!(key in present)) print value[key]
    }
    if (before_table && missing) print ""
    root_emitted = 1
  }
  {
    if (!in_table && $0 ~ /^[[:space:]]*\[\[?/) {
      emit_root(1)
      in_table = 1
    }
    if (!in_table) {
      for (i = 1; i <= count; i++) {
        key = order[i]
        expression = "^[[:space:]]*" key "[[:space:]]*="
        if ($0 ~ expression) {
          root[++root_count] = value[key]
          present[key] = 1
          next
        }
      }
      root[++root_count] = $0
      next
    }
    print
  }
  END {
    if (!in_table) emit_root(0)
  }
' "$MANAGED_VALUES" "$TARGET_INPUT" >"$WORK_FILE"

# 管理対象の table とその子 table を削除し、source 側の定義を末尾に追加する。
# marker に囲まれた旧定義も取り除くため、source から共有 table を削除した場合も追従する。
# それ以外の MCP server、project trust、Desktop/プラグイン設定は untouched のまま残す。
WITHOUT_MANAGED_TABLES="$(mktemp "${TMPDIR:-/tmp}/codex-config-without-managed-tables.XXXXXX")"
awk -v managed_table_roots="$MANAGED_TABLE_ROOTS" '
  BEGIN {
    while ((getline table_root < managed_table_roots) > 0) managed[table_root] = 1
    close(managed_table_roots)
  }
  function is_managed_table(table, root) {
    for (root in managed) {
      if (table == root || index(table, root ".") == 1) return 1
    }
    return 0
  }
  $0 == "# >>> dotfiles managed MCP servers >>>" {
    in_managed_block = 1
    drop = 0
    next
  }
  $0 == "# <<< dotfiles managed MCP servers <<<" {
    in_managed_block = 0
    drop = 0
    next
  }
  $0 == "# >>> dotfiles managed tables >>>" {
    in_managed_block = 1
    drop = 0
    next
  }
  $0 == "# <<< dotfiles managed tables <<<" {
    in_managed_block = 0
    drop = 0
    next
  }
  in_managed_block { next }
  /^[[:space:]]*\[\[?/ {
    drop = 0
    header = $0
    sub(/^[[:space:]]*\[\[?/, "", header)
    sub(/\]\].*$/, "", header)
    sub(/\].*$/, "", header)
    if (is_managed_table(header)) {
      drop = 1
    }
    if (drop) {
      next
    }
  }
  !drop { print }
' "$WORK_FILE" >"$WITHOUT_MANAGED_TABLES"

INCLUDE_TABLES=0
if [ -s "$MANAGED_TABLES" ]; then
  INCLUDE_TABLES=1
fi

awk -v managed_tables="$MANAGED_TABLES" -v include_tables="$INCLUDE_TABLES" '
  {
    lines[NR] = $0
    if ($0 !~ /^[[:space:]]*$/) last_content = NR
  }
  END {
    for (i = 1; i <= last_content; i++) print lines[i]
    if (last_content && include_tables) print ""
    if (include_tables) {
      print "# >>> dotfiles managed tables >>>"
      while ((getline line < managed_tables) > 0) print line
      close(managed_tables)
      print "# <<< dotfiles managed tables <<<"
    }
  }
' "$WITHOUT_MANAGED_TABLES" >"$WORK_FILE"

if [ -e "$TARGET" ] && cmp -s "$WORK_FILE" "$TARGET"; then
  echo "  [OK]   $TARGET (共有設定と一致)"
  exit 0
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo "  [SYNC] $TARGET"
  if [ -e "$TARGET" ]; then
    diff -u "$TARGET" "$WORK_FILE" || true
  else
    diff -u /dev/null "$WORK_FILE" || true
  fi
  exit 0
fi

if [ -e "$TARGET" ]; then
  TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
  BACKUP="$TARGET.backup-$TIMESTAMP"
  cp "$TARGET" "$BACKUP"
  echo "  [BACKUP] $TARGET -> $BACKUP"
fi

mv "$WORK_FILE" "$TARGET"
WORK_FILE=""
echo "  [SYNC] $TARGET"
