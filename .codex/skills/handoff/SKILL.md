---
name: handoff
description: Summarize the current work session into a durable Obsidian handoff note so a later Codex session can resume it without reading the full history.
---

# Session handoff

Write a compact handoff note when the user asks to hand off, preserve session
state, or prepare work for a later session. The goal is to make the next
session productive from this note alone, not to transcribe the conversation.

Save the note at:

```text
ClaudeCode/<project>/Handoff/<timestamp>_<branch>_<topic>.md
```

- `<project>` is the Git root directory name, or the current directory name
  outside Git.
- `<timestamp>` is `YYYY-MM-DDTHH-MM-SS`.
- `<branch>` is the final segment of the branch name, truncated to 24
  characters.
- `<topic>` is a Japanese summary of the session in at most 15 characters;
  replace `/` with `_`.

Use `~/.codex/skills/obsidian-safe-ops/scripts/obs.sh write` with a temporary
body file. Never use raw `obsidian ... content=`. Check `git status --short`
and recent history when they matter, and always record uncommitted changes.

Keep the note within about 40 lines:

```markdown
## 目的
<達成しようとしていたこと>

## 現在の状態
- ブランチ: <branch>（<最新 commit>）
- 未コミット変更: <あり（対象）/ なし>
- <動いていること・未確認事項>

## 決定事項
- <決定> — 理由: <理由>

## 残タスク
- [ ] <次の具体的な作業>

## 関連ファイル
- <path:line> — <説明>

## 注意点・罠
- <次のセッションが避けるべきこと>
```

作成後はノートの vault 相対パスを伝える。次回は `resume-handoff` を使えることも案内する。
