#!/usr/bin/env bash
# git worktree を「作った直後から動く」状態にする。
#
#   worktree_sync.sh [--dry-run] [<worktree パス>]   (省略時は $PWD)
#
# やることは 3 つ:
#   1. .env などの gitignore されたローカル設定をメイン worktree からリンクする
#   2. direnv / mise の許可を通し、mise のツールを揃える
#   3. serena MCP を登録する (Claude Code の local scope はディレクトリに紐づくため)
#
# - メイン worktree 側の実体へシンボリックリンクを張る。片方で書き換えれば全 worktree に
#   反映され、古いコピーが残らない (worktree 側のツールが .env を書き換えるとメインにも
#   波及する点だけ注意)。
# - 対象は「メイン worktree に存在する ignore 済みファイル」のうちパターンに一致したもの。
#   ignore 済みの列挙は git 自身にやらせる (グローバル/ローカルの gitignore を両方見るため)。
#   node_modules のような ignore 済みディレクトリは --directory でまとめて 1 エントリになる
#   ので中まで走査しない。
# - 既に同名のファイル/リンクが worktree 側にあれば触らない (上書きしない)。
# - 新規 worktree 作成時に worktree_session.sh / new-worktree から呼ばれるほか、後から
#   .env が増えたときに手で叩き直してもよい (べき等)。
#
# 対象パターンは下記のデフォルトに加え、git config で追加できる (複数指定可):
#
#   git config --add tmux.worktreeSync '.mise.local.toml'
#
# パターンはリポジトリルートからの相対パスに対する glob。'*' は '/' も跨ぐので '*.env' は
# 深い階層の .env にも当たる。'/' を含むパターンは '*/<パターン>' でも照合するため、
# '.claude/settings.local.json' はサブディレクトリ配下のものにも当たる。
#
# macOS 標準の bash 3.2 でも動くように書いている。
set -uo pipefail

DEFAULT_PATTERNS='.env
*.env
.claude/settings.local.json'

DRY_RUN=0
if [ "${1:-}" = "--dry-run" ]; then DRY_RUN=1; shift; fi

die() { echo "worktree_sync: $*" >&2; exit 1; }

target="${1:-$PWD}"
[ -d "$target" ] || die "ディレクトリがありません: $target"
target="$(cd "$target" && pwd -P)" || die "解決できません: $target"

git -C "$target" rev-parse --git-dir >/dev/null 2>&1 || die "git リポジトリではありません: $target"

# --porcelain の先頭エントリがメイン worktree。
main="$(git -C "$target" worktree list --porcelain | head -1 | sed 's/^worktree //')"
[ -n "$main" ] && [ -d "$main" ] || die "メイン worktree を特定できませんでした"
main="$(cd "$main" && pwd -P)"

# 自分自身がメインなら持ち込む先が無い。
[ "$main" = "$target" ] && exit 0

patterns="$DEFAULT_PATTERNS
$(git -C "$main" config --get-all tmux.worktreeSync 2>/dev/null || true)"

# core.quotePath=false: 日本語などを \xxx にエスケープさせない。
ignored="$(git -C "$main" -c core.quotePath=false \
  ls-files --others --ignored --exclude-standard --directory 2>/dev/null || true)"

n=0
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  case "$rel" in */) continue ;; esac   # ディレクトリエントリは対象外

  matched=0
  while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    # shellcheck disable=SC2254  # パターンとして展開させたいので引用しない
    case "$rel" in $pat|*/$pat) matched=1; break ;; esac
  done <<INNER
$patterns
INNER
  [ "$matched" -eq 1 ] || continue

  src="$main/$rel"
  dst="$target/$rel"
  [ -f "$src" ] || continue
  if [ -e "$dst" ] || [ -L "$dst" ]; then continue; fi

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  DRY: ln -s $src $dst"
  else
    mkdir -p "$(dirname "$dst")" && ln -s "$src" "$dst" || { echo "  [FAIL] $rel" >&2; continue; }
    echo "  linked: $rel"
  fi
  n=$((n + 1))
done <<INNER
$ignored
INNER

[ "$n" -gt 0 ] && echo "worktree_sync: $n 件のローカル設定をリンクしました" >&2

# --- 実行環境の許可 -----------------------------------------------------------
# direnv の許可は .envrc の絶対パスに紐づくので worktree ごとに取り直しになる。
# mise の trust はメイン worktree の同等パスが trust 済みなら共有されるが、paranoid
# モードでは共有されない (ブランチによって内容が違いうるため) ので明示的に叩いておく。
# どちらも冪等なので既に許可済みでも実行してよい。
allow() { # allow <表示名> <コマンド...>
  local label="$1"; shift
  if [ "$DRY_RUN" -eq 1 ]; then echo "  DRY: $*"; return 0; fi
  if "$@" >/dev/null 2>&1; then echo "  $label"; else echo "  [FAIL] $*" >&2; fi
}

# direnv が読むのは .envrc、無ければ .env の「先に見つかった 1 つだけ」。
# .env しか無いリポジトリでも (1 でリンクを張った結果) blocked と言われるので許可する。
if command -v direnv >/dev/null 2>&1; then
  for f in .envrc .env; do
    if [ -e "$target/$f" ]; then
      allow "direnv allow: $f" direnv allow "$target/$f"
      break
    fi
  done
fi

has_mise_config=0
if command -v mise >/dev/null 2>&1; then
  for f in mise.toml .mise.toml mise.local.toml .mise.local.toml \
           .config/mise.toml mise/config.toml .mise/config.toml .config/mise/config.toml; do
    [ -f "$target/$f" ] || continue
    has_mise_config=1
    allow "mise trust: $f" mise trust "$target/$f"
  done
fi

# ツールの実体は ~/.local/share/mise/installs にバージョン単位で置かれて worktree 間で
# 共有されるので、たいていは何もせずに終わる (実測 0.05 秒)。ブランチが mise.toml の
# バージョンを上げている場合だけ実際にインストールが走る。
# 時間のかかる処理なので出力はそのまま流す (握り潰さない)。
if [ "$has_mise_config" -eq 1 ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  DRY: mise install -C $target"
  else
    mise install -C "$target" || echo "  [FAIL] mise install" >&2
  fi
fi

# --- serena MCP の登録 --------------------------------------------------------
# claude mcp add の既定スコープ (local) は「そのディレクトリ」に紐づくので worktree ごとに要る。
# 既に登録済みなら claude mcp add も no-op だが、余計な出力を避けるため get で先に見る。
if command -v claude >/dev/null 2>&1; then
  if ! (cd "$target" && claude mcp get serena >/dev/null 2>&1); then
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "  DRY: claude mcp add serena (cwd: $target)"
    elif (cd "$target" && claude mcp add serena -- uvx --from git+https://github.com/oraios/serena \
            serena start-mcp-server --context claude-code --project "$target" >/dev/null 2>&1); then
      echo "  claude mcp add: serena"
    else
      echo "  [FAIL] claude mcp add serena" >&2
    fi
  fi
fi

exit 0
