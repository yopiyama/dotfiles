---
name: resume-handoff
description: "Handoff ノートからのセッション再開。/handoff で書き出された Obsidian の引き継ぎノート（最新 or 指定されたもの）を読み、残タスクと現在のリポジトリ状態を突き合わせて作業を継続する。built-in の /resume（会話履歴の復元）とは別物。"
disable-model-invocation: true
argument-hint: "[ノート名の一部（省略時は最新）]"
allowed-tools: Bash(obsidian files:*), Bash(obsidian read:*), Bash(git status:*), Bash(git log:*), Bash(git branch:*), Bash(git rev-parse:*)
---

# Resume Handoff — Handoff ノートからのセッション再開

`/handoff` が書き出した引き継ぎノートを読み、前セッションの続きから作業する。built-in の `/resume`（同一会話履歴の復元）とは異なり、履歴は引き継がず要約ノートだけで再開する。

## 手順

1. **ノートの特定**: `obsidian files folder="ClaudeCode/<プロジェクト名>/Handoff"` で一覧を取得する（プロジェクト名は `basename "$(git rev-parse --show-toplevel)"`）
   - 引数 `$ARGUMENTS` が指定されていれば、それを含む名前のノートを選ぶ
   - 指定がなければ最新のノートを選ぶ（ファイル名が stamp 始まりなので辞書順の末尾が最新）
   - ノートが 1 つもなければ「Handoff ノートが見つからない」と伝えて終了する
2. **読み込み**: `obsidian read path="<ノートのパス>"` で内容を読む。Handoff ノート以外の探索（Conversations ログの遡り読み等）はしない — このノートだけで再開できるのが handoff の契約であり、足りなければ足りないと報告する
3. **現状との突き合わせ**: `git status --short` / `git log --oneline -5` / `git branch --show-current` を実行し、ノートの「現在の状態」と比較する
   - ブランチ・コミット・未コミット変更がノートの記載とずれている場合（handoff 後に手作業があった等）は、差分を報告してから進める
4. **再開**: ユーザーに以下を簡潔に提示してから、残タスクの先頭に着手する（着手前にユーザーの意向確認が必要な残タスクだけ確認する）:
   - 読んだノート名
   - 目的と残タスクの要約（数行）
   - 現状とのずれ（あれば）

## 完了時の後始末

残タスクをすべて消化したら、ノートのチェックボックスの更新をユーザーに提案する（`obsidian task` での更新は書き込み系のため、勝手には行わない）。
