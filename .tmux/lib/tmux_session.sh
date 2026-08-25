# tmux セッション生成の共通部品。launch_project.sh と worktree_session.sh から source する。
# 単体実行はしない (shebang なし・実行権限なし)。呼び出し側が set -euo pipefail 済みである前提。
#
# ウィンドウ/ペイン定義は 1 行 1 レコードのテキストで受け渡す。区切りは US (0x1f):
# cmd に含まれうるタブやスペースと衝突しないため。
#   window <US> 名前 <US> cmd
#   pane   <US> split(right|bottom) <US> size <US> cmd   ← 直前の window に属する追加ペイン
#
# macOS 標準の bash 3.2 でも動くように書いている (mapfile / nameref を使わない)。

TS_US=$'\x1f'

# セッションが存在するか。名前は "=" 付きで完全一致させる (前方一致を避ける)。
ts_session_exists() { tmux has-session -t "=$1" 2>/dev/null; }

# tmux の中なら switch-client、外なら attach-session。
# 引数は tmux のターゲットそのもの ("=<名前>" か "$<id>") を渡す。
ts_attach() {
  if [ -n "${TMUX:-}" ]; then tmux switch-client -t "$1"; else tmux attach-session -t "$1"; fi
}

# 既存セッションを "id <TAB> 名前 <TAB> @worktree_path" の 1 行 1 セッションで出す。
# tmux は -F の出力に含まれる制御文字を '_' に潰すので、1 つの -F にタブを入れて
# 区切ることはできない。id だけを -F で取り、名前とオプションはセッションごとに
# 引いてシェル側 (printf) で連結する。
# なお set-option / show-options / display-message の -t は target-pane 扱いで
# "=<名前>" を解釈しないため、これらには id を渡すこと。
ts_session_map() {
  local sid
  { tmux list-sessions -F '#{session_id}' 2>/dev/null || true; } | while IFS= read -r sid; do
    [ -n "$sid" ] || continue
    printf '%s\t%s\t%s\n' "$sid" \
      "$(tmux display-message -p -t "$sid" '#{session_name}' 2>/dev/null || true)" \
      "$(tmux show-options -t "$sid" -qv @worktree_path 2>/dev/null || true)"
  done
}

# ts_session_id <セッション名> → セッション id ($N)。無ければ空。
ts_session_id() {
  ts_session_map | awk -F'\t' -v n="$1" '$2 == n { print $1; exit }'
}

# 新規セッションに渡すサイズを TS_SIZE_ARGS に用意する。
# detached で作るセッションは既定 80x24 になり、%指定の分割サイズがその幅で計算される。
# attach 時のリサイズで tmux は増分をペインへほぼ均等に配り比率を保存しないため、
# 作成時点で実クライアントのサイズを渡しておく。
# サイズが取れないとき (TERM 未設定など) は空にして tmux の既定サイズに任せる。
ts_size_args() {
  local w="" h=""
  TS_SIZE_ARGS=()
  if [ -n "${TMUX:-}" ]; then
    # popup 内の tput は popup サイズを返すため、外側クライアントのサイズを tmux に問い合わせる
    w="$(tmux display-message -p '#{client_width}' 2>/dev/null || true)"
    h="$(tmux display-message -p '#{client_height}' 2>/dev/null || true)"
  else
    w="$(tput cols 2>/dev/null || true)"
    h="$(tput lines 2>/dev/null || true)"
  fi
  case "$w" in ''|*[!0-9]*) return 0 ;; esac
  case "$h" in ''|*[!0-9]*) return 0 ;; esac
  TS_SIZE_ARGS=(-x "$w" -y "$h")
}

# ウィンドウの分割が済んだら最初のペイン (メイン) にフォーカスを戻す
_ts_finish_window() {
  if [ -n "$_ts_panes_added" ]; then tmux select-pane -t "$_ts_win_pane"; fi
  return 0
}

# ts_build_session <セッション名> <作業ディレクトリ>
# レコードは stdin から読む。detached のセッションを作って最初のウィンドウを選択した状態で返る
# (attach は呼び出し側の責務)。レコードが 1 つも無ければ 1 を返す。
ts_build_session() {
  local name="$1" path="$2"
  local kind f1 f2 f3 split_flag pane_id
  local first_name="" wname=""
  local split_args

  _ts_win_pane=""
  _ts_panes_added=""
  ts_size_args

  while IFS="$TS_US" read -r kind f1 f2 f3; do
    case "$kind" in
      window)
        _ts_finish_window
        wname="$f1"
        _ts_panes_added=""
        if [ -z "$first_name" ]; then
          # -n で名前を明示すると automatic-rename はそのウィンドウで自動的に無効化される
          # bash 3.2 + set -u では空配列の "${a[@]}" が unbound になるので +展開で守る
          _ts_win_pane="$(tmux new-session -d ${TS_SIZE_ARGS[@]+"${TS_SIZE_ARGS[@]}"} -s "$name" -n "$wname" -c "$path" -P -F '#{pane_id}')"
          first_name="$wname"
        else
          _ts_win_pane="$(tmux new-window -t "=$name:" -n "$wname" -c "$path" -P -F '#{pane_id}')"
        fi
        if [ -n "$f2" ]; then tmux send-keys -t "$_ts_win_pane" "$f2" C-m; fi
        ;;
      pane)
        case "$f1" in
          right|h)  split_flag=-h ;;
          bottom|v) split_flag=-v ;;
          *) echo "不正な split 指定: $f1 (right / bottom)" >&2; return 1 ;;
        esac
        # 直前に作ったペイン (= アクティブペイン) を分割していく
        split_args=(split-window "$split_flag" -t "=$name:$wname" -c "$path" -P -F '#{pane_id}')
        if [ -n "$f2" ]; then split_args+=(-l "$f2"); fi
        pane_id="$(tmux "${split_args[@]}")"
        if [ -n "$f3" ]; then tmux send-keys -t "$pane_id" "$f3" C-m; fi
        _ts_panes_added=1
        ;;
    esac
  done

  _ts_finish_window
  [ -n "$first_name" ] || return 1
  tmux select-window -t "=$name:$first_name"
}
