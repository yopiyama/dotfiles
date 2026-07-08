---
name: pr-comments
description: "GitHub PR のレビューコメントの洗い出しとタスク化。固定スクリプトで reviews / review threads / issue comments をまとめて取得し、分類して Obsidian のタスクノートに書き出す。「PR コメントをリストアップして」「レビューコメントをタスク化して」「PR の指摘を洗い出して」と言われたときに起動。"
allowed-tools: Bash(~/.claude/skills/pr-comments/scripts/fetch-pr-comments.sh:*), Bash(gh pr view:*), Bash(git rev-parse:*), Bash(date:*), Bash(obsidian read:*), Bash(obsidian create:*), Bash(obsidian files:*), Bash(obsidian open:*)
---

# PR Comments — レビューコメントの洗い出しとタスク化

GitHub PR に付いたコメントを固定スクリプトで一括取得し、分類・一覧化して Obsidian のタスクノートに書き出す。`gh api` + インライン Python をその場で組み立てるのは禁止（毎回承認が必要になる）。取得は必ず下記スクリプトで行う。

## 手順

### 1. コメント取得

```bash
~/.claude/skills/pr-comments/scripts/fetch-pr-comments.sh [PR番号 | PR URL] [オプション]
```

- 引数省略時はカレントブランチの PR を自動解決する
- ユーザーが「このレビュー以降」と URL を貼った場合、`#pullrequestreview-<ID>` の ID を `--since <ID>` に渡す（その review 自身を含む）。日時指定なら ISO8601 も可
- 解決済み (resolved) スレッドはデフォルトで除外される。全件見たいと言われたら `--include-resolved`
- 出力はデフォルト JSON。`--format md` で人間向け Markdown

### 2. 分類して一覧提示

タスク化の前に、必ず一覧をユーザーに提示する。

- コメント本文の先頭ラベル（`[IMO]` `[ASK]` `[NITS]` `[WANT]` `[Tweet]` `[質問]` など）を拾って分類する。ラベルが無ければ内容から «要修正 / 要回答 / 要議論 / 対応不要» を推定する
- 各項目は「指摘者 / `path:line` / ラベル / 一行要約」で提示。「対応不要」とスレッド内で明言されているものはその旨を付記する
- スレッドに返信が付いている場合は最新の議論状態を要約に反映する

### 3. Obsidian タスクノートへ書き出し

保存先: `ClaudeCode/<プロジェクト名>/Tasks/PR-<PR番号>.md`

- プロジェクト名: `basename "$(git rev-parse --show-toplevel)"`（対象リポジトリの名前。dotfiles ではなく PR のリポジトリ）
- 書き込みは obsidian CLI（connect-obsidian スキル参照）で行う。素の Write は使わない

**既存ノートがある場合は先に `obsidian read` で読み、チェック済み `- [x]` の状態と手書きの追記を保持したままマージする**（`overwrite` で無断で潰さない）。

フォーマット:

```markdown
---
pr: <PR URL>
repo: <owner/name>
updated: <YYYY-MM-DD>
---

# PR #<番号> レビュー対応タスク

## 要修正
- [ ] `path/file.go:54` [IMO] 一行要約 — @指摘者 ([comment](URL))

## 要回答・要確認
- [ ] ...

## 要議論
- [ ] ...

## 対応不要（記録のみ）
- 一行要約 — @指摘者 ([comment](URL))
```

- 1 スレッド = 1 タスク。チェックボックスの行に `path:line`・ラベル・要約・指摘者・コメント URL を必ず含める
- 「対応不要」セクションはチェックボックスにしない
- 書き出し後、ノートのパスをユーザーに伝える（必要なら `obsidian open` で開く）

## 注意

- スクリプトは gh CLI の認証を前提とする。失敗したら stderr をそのまま提示する
- タスク管理先の変更（TaskCreate / Notion 等）をユーザーが明示した場合のみ、そちらに切り替える
