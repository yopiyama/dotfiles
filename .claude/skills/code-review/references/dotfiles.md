# dotfiles プロジェクト固有レビュー観点

対象: yopiyama/dotfiles（install.sh による symlink 配布型の dotfiles 管理）。

このファイルのセクション見出しには `[Logic]` / `[Design]` タグを付けている。
SKILL.md ステップ 6 の固定マッピングに該当セクション名はないため、
**タグに従って分配する**こと（`[Logic]` → ダ・ヴィンチちゃん、`[Design]` → ギルガメッシュ、Codex には全セクション）。

## [Logic] shell スクリプト

- 実行スクリプトに `set -euo pipefail` が付いているか（source 前提の lib は除く）
- 変数展開のクォート漏れ。空文字・未定義変数のときの挙動
- macOS 標準 bash 3.2 で動くか（連想配列、`${var,,}` 等 bash 4+ 機能の混入）
- `set -e` 下で失敗を許容したい箇所の `|| true` の付け忘れ / 意図しない握り潰し
- パイプの早期 close でハングするコマンドがないか（`obsidian help | head` 等）

## [Logic] hooks

- `.claude/hooks/*.sh` の変更に対応する `test-*.sh` の更新と実行
- ノート命名・保存先ロジックは `obsidian-note-lib.sh` に一元化する。各スクリプトへコピーしない（wikilink がノート名の完全一致で成立しているため、片方だけ変えるとリンクが黙って切れる）
- フック内から `claude` CLI を呼ぶ場合は `--safe-mode --no-session-persistence` を付ける（Stop フックの再発火防止）

## [Design] install.sh / 配布

- トップレベルの新規ファイル・ディレクトリを追加したとき、`install.sh` の `LINKS` への追随漏れがないか（`.claude/skills` 等ディレクトリ丸ごとリンクの配下に置くファイルは不要）
- 配布するサンプルファイルの命名は `<名前>.sample` に統一

## [Design] Claude Code 設定（skills / agents / settings.json）

- SKILL.md の frontmatter は `allowed-tools` を使う（`tools:` は agent 定義専用のフィールドで、skill では無視される）
- スキルが新しいスクリプトを実行する場合、`settings.json` の `permissions.allow` への追随があるか
- `permissions.deny`（curl / git push / sed -i 等）と矛盾する手順をスキルや agent 定義に書いていないか（deny が優先されて実行時に詰まる）
- サブエージェントに `obsidian` CLI を使わせていないか（多重起動回避のため、サブエージェントは vault を素の Read/Grep で直接扱う）
- 秘匿情報（トークン・メールアドレス・マシン固有パス）を設定・スキルにハードコードしていないか

## [Design] ドキュメント整合

- CLAUDE.md に書かれたルールと実装の乖離が生じていないか（`LINKS` の説明、symlink 実体編集ルール等）
