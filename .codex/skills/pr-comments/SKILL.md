---
name: pr-comments
description: Collect GitHub PR reviews and threads, present a classified list, and create or update durable Obsidian task notes for the requested review work.
---

# PR review comments

Use the fixed scripts below. Do not reimplement their GraphQL queries, task
file naming, or Obsidian write flow inline.

```sh
~/.codex/skills/pr-comments/scripts/fetch-pr-comments.sh
~/.codex/skills/pr-comments/scripts/pr-task-notes.sh
```

The scripts share `obsidian-safe-ops` for verified vault I/O. For the parent
task note's Bases view, follow `obsidian-bases`; for child note Markdown,
follow `obsidian-markdown`.

## Collect and classify

Run `fetch-pr-comments.sh [PR number | PR URL]`. It resolves the current
branch's PR when no argument is given and excludes resolved threads by default.
Use `--include-resolved` only when the user asks for all threads, and use
`--since <review-id|UTC ISO8601>` for a requested time or review boundary.

Before creating task notes, present a classified list: reviewer, `path:line`,
label, and one-line summary. Preserve the distinction between required changes,
questions, discussion, and explicitly unnecessary work.

## Create or update task notes

The user asking to taskify or synchronize comments authorizes these vault
writes. Store work under:

```text
ClaudeCode/<project>/Tasks/PR-<number>.md
ClaudeCode/<project>/Tasks/PR-<number>/<index>_<summary>.md
```

Use `pr-task-notes.sh` for every task-note operation:

1. `init` the parent note with PR URL, repository, title, and scope.
2. `list` existing child notes before updating them.
3. Match existing items by `comment_url`, not only by source line.
4. `read` an existing child before rewriting it. Preserve manual `補足`,
   `回答案`, `status`, and `memo`; append new thread comments in chronological
   order.
5. Use `next-index` only for new threads and `put` to write content. Existing
   indices and filenames must remain stable.
6. Update state only through `set-status`: `ready`, `waiting`, `local`, `hold`,
   or `done`.

On synchronization, fetch with `--include-resolved`; mark resolved threads
`done`, but never overwrite a user-selected `done` or `hold` state. Summarize
new, resolved, and replied-to items when finished.

If either script fails, stop and show its stderr. Do not fall back to raw
`obsidian` content commands or ad-hoc `gh api` queries.
