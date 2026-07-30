# plugins_local

この端末だけで使う nvim プラグイン定義を置くディレクトリ。

- ここに置いた `*.lua` は git 管理外（`.gitignore` でこの README 以外を無視）。
- `lua/config/lazy.lua` の `spec` から `{ import = "plugins_local" }` で読み込まれる。
- 書き方は `lua/plugins/` と同じ（spec テーブルを `return` する）。
- 用途: 社内リポジトリのローカルプラグイン（`dir = vim.fn.expand("~/ghq/...")`）や、
  検証中で共有したくない設定など。
