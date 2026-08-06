---
name: handoff
description: "セッション引き継ぎノートの書き出し。現在のセッションの目的・決定事項・残タスク・関連 file:line を Obsidian の Handoff ノートに要約し、新しいセッションが /resume-handoff で読んで再開できるようにする。コンテキストが肥大化したセッションを畳むときに使う。"
disable-model-invocation: true
allowed-tools: Bash(~/.claude/skills/connect-obsidian/scripts/obs.sh write:*), Bash(~/.claude/skills/connect-obsidian/scripts/obs.sh ls:*), Bash(git status:*), Bash(git log:*), Bash(git diff:*), Bash(git branch:*), Bash(git rev-parse:*), Bash(date:*)
---

# Handoff — セッション引き継ぎノートの書き出し

現在のセッションの状態を Obsidian の Handoff ノートに要約する。目的は、コンテキストが肥大化したセッションを安全に捨て、新しいセッションが `/resume-handoff` でこのノートだけを読んで作業を再開できるようにすること（会話履歴は毎ターン再読込されるため、長寿命セッションを畳むことが最大のトークン節約になる）。

## 保存先

`ClaudeCode/<プロジェクト名>/Handoff/<stamp>_<ブランチ>_<トピック>.md`

- プロジェクト名: `basename "$(git rev-parse --show-toplevel)"`（非 git dir なら cwd の basename）
- stamp: `date +%Y-%m-%dT%H-%M-%S`
- ブランチ: 現在のブランチ名の最後のセグメント（`feature/foo-bar` → `foo-bar`）。24 文字を超える場合は切り詰める
- トピック: セッションの主題を日本語 15 文字以内で要約したもの（`/` は `_` に置換）

この命名は log-to-obsidian フックのセッションログノートの慣習（`ClaudeCode/<プロジェクト>/Conversations/`）に合わせている。会話の全文ログはフックが別途残すため、**このノートに会話の経緯を書き写さない**。

## 手順

1. 必要に応じて `git status --short` / `git log --oneline -5` で現在の状態を確認する（未コミット変更の有無は必ずノートに反映する）
2. 下のテンプレートでノート本文を作成する
3. 本文を scratchpad の一時ファイルに書き、そのパスを渡して書き込む

   ```bash
   ~/.claude/skills/connect-obsidian/scripts/obs.sh write \
     "ClaudeCode/<プロジェクト名>/Handoff/<ファイル名>.md" <本文ファイル>
   ```

   - **`obsidian create ... content='<本文>'` を直に叩かない**。CLI は本文を argv でソケットに流すため、バッファ境界でマルチバイト文字が壊れる（1 文字が U+FFFD に化ける）
   - obs.sh はファイル経由で書いて読み直して検証するので、リテラル `\n`・`\t` やバッククォート・`$`・シングルクォートをそのまま含められる
4. 作成したノートのパスをユーザーに提示し、「新しいセッションで `/resume-handoff` を実行すれば再開できる」と案内する（built-in の `/resume` ではない点に注意）

## ノートテンプレート

```markdown
## 目的
<このセッションで達成しようとしていたこと。1〜3 行>

## 現在の状態
- ブランチ: <ブランチ名>（<最新コミットの hash と件名>）
- 未コミット変更: <あり（対象ファイル）/ なし>
- <動いているもの / まだ動かないもの>

## 決定事項
- <決定内容> — 理由: <なぜそうしたか>

## 残タスク
- [ ] <次にやること。具体的に>
- [ ] <その次>

## 関連ファイル
- <file_path:line> — <一言説明>

## 注意点・罠
- <ハマったこと、次のセッションが同じ穴に落ちないための情報>
```

書く量の目安は全体で 40 行以内。resume 側がこれを丸ごと読むため、詳細すぎる記述はそのままコストになる。迷ったら「次のセッションの自分が最初の 5 分で必要とする情報か」で取捨選択する。
