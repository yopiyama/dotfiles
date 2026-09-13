#!/usr/bin/env bash
#
# dotfiles 側の共有 Codex 設定を ~/.codex/config.toml に同期する。
#
# config.shared.toml に定義したトップレベルの単一行 TOML 値と
# [mcp_servers.<name>] table を正として上書きする。Codex Desktop が管理する
# project trust、UI 状態、plugins、共有対象外の MCP とその認証情報は保持する。
# TOML 全体を置換しないため、端末固有の自動生成設定は壊さない。
#
#   scripts/sync-codex-config.sh
#   scripts/sync-codex-config.sh --dry-run
#
# テスト等では --source / --target で対象を差し替えられる。
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$REPO/.config/config.shared.toml"
TARGET="$HOME/.codex/config.toml"
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: sync-codex-config.sh [--dry-run] [--source PATH] [--target PATH]

Synchronize top-level, single-line TOML assignments and [mcp_servers.<name>]
tables from the source file into the target Codex config. Managed source values
and MCP servers are authoritative; every other target setting is preserved.
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

# 管理用ソースは、トップレベルの単一行 key = value と
# [mcp_servers.<name>]（その子 table を含む）だけを受け付ける。これにより任意の
# TOML を雑に書き換えず、同期範囲を明示的に保つ。
MANAGED_VALUES="$(mktemp "${TMPDIR:-/tmp}/codex-managed-values.XXXXXX")"
MANAGED_MCP="$(mktemp "${TMPDIR:-/tmp}/codex-managed-mcp.XXXXXX")"
MANAGED_MCP_SERVERS="$(mktemp "${TMPDIR:-/tmp}/codex-managed-mcp-servers.XXXXXX")"
cleanup() {
  rm -f "$MANAGED_VALUES" "$MANAGED_MCP" "$MANAGED_MCP_SERVERS" \
    "${WITHOUT_MANAGED_MCP:-}" "${WORK_FILE:-}"
}
trap cleanup EXIT HUP INT TERM

awk -v managed_mcp="$MANAGED_MCP" -v managed_mcp_servers="$MANAGED_MCP_SERVERS" '
  function invalid(message) {
    print message > "/dev/stderr"
    exit 2
  }
  /^[[:space:]]*($|#)/ { next }
  /^[[:space:]]*\[/ {
    line = $0
    sub(/^[[:space:]]*/, "", line)
    if (line !~ /^\[mcp_servers\.[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)*\][[:space:]]*(#.*)?$/) {
      invalid("config.shared.toml で許可される table は [mcp_servers.<name>] だけです: " $0)
    }
    in_mcp = 1
    print $0 >> managed_mcp
    server = line
    sub(/^\[mcp_servers\./, "", server)
    sub(/[.\]].*$/, "", server)
    if (!seen_server[server]++) print server >> managed_mcp_servers
    next
  }
  {
    line = $0
    sub(/^[[:space:]]*/, "", line)
    if (line !~ /^[A-Za-z0-9_-]+[[:space:]]*=/) {
      invalid("config.shared.toml の形式が不正です: " $0)
    }
    if (in_mcp) {
      print $0 >> managed_mcp
      next
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

[ -s "$MANAGED_VALUES" ] || [ -s "$MANAGED_MCP" ] || {
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
awk -F '\t' '
  FNR == NR {
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

# 管理対象の MCP server table とその子 table を削除し、source 側の定義を末尾に追加する。
# marker に囲まれた旧定義も取り除くため、source から共有 MCP を削除した場合も追従する。
# それ以外の MCP server、project trust、Desktop/プラグイン設定は untouched のまま残す。
WITHOUT_MANAGED_MCP="$(mktemp "${TMPDIR:-/tmp}/codex-config-without-managed-mcp.XXXXXX")"
awk -v managed_mcp_servers="$MANAGED_MCP_SERVERS" '
  BEGIN {
    while ((getline server < managed_mcp_servers) > 0) managed[server] = 1
    close(managed_mcp_servers)
  }
  $0 == "# >>> dotfiles managed MCP servers >>>" {
    in_managed_block = 1
    next
  }
  $0 == "# <<< dotfiles managed MCP servers <<<" {
    in_managed_block = 0
    next
  }
  in_managed_block { next }
  /^[[:space:]]*\[\[?/ {
    drop = 0
    if ($0 ~ /^[[:space:]]*\[mcp_servers\./) {
      header = $0
      sub(/^[[:space:]]*\[mcp_servers\./, "", header)
      sub(/[.\]].*$/, "", header)
      if (header in managed) drop = 1
    }
  }
  !drop { print }
' "$WORK_FILE" >"$WITHOUT_MANAGED_MCP"

INCLUDE_MCP=0
if [ -s "$MANAGED_MCP" ]; then
  INCLUDE_MCP=1
fi

awk -v managed_mcp="$MANAGED_MCP" -v include_mcp="$INCLUDE_MCP" '
  {
    lines[NR] = $0
    if ($0 !~ /^[[:space:]]*$/) last_content = NR
  }
  END {
    for (i = 1; i <= last_content; i++) print lines[i]
    if (last_content && include_mcp) print ""
    if (include_mcp) {
      print "# >>> dotfiles managed MCP servers >>>"
      while ((getline line < managed_mcp) > 0) print line
      close(managed_mcp)
      print "# <<< dotfiles managed MCP servers <<<"
    }
  }
' "$WITHOUT_MANAGED_MCP" >"$WORK_FILE"

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
