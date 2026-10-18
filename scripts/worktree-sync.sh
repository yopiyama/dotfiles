#!/usr/bin/env bash
# 旧 tmux helper を中立なコマンド名で公開する互換エントリポイント。
set -euo pipefail

exec "$HOME/.tmux/worktree_sync.sh" "$@"
