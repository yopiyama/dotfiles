---
name: resume-handoff
description: Resume work from an Obsidian handoff note, comparing the recorded state with the current Git repository before continuing.
---

# Resume a session handoff

Use this skill when the user asks to resume a handoff note. This is distinct
from restoring a conversation history: read only the handoff note, then verify
the current repository state.

1. Determine the project name from the Git root, or the current directory when
   outside Git.
2. List `ClaudeCode/<project>/Handoff` with
   `~/.codex/skills/obsidian-safe-ops/scripts/obs.sh ls`.
   - If the user named a note, choose the matching one.
   - Otherwise choose the lexicographically latest timestamped note.
   - If none exists, report that and stop.
3. Read the selected note with `obs.sh read`. Do not search old conversation
   logs to fill gaps; report missing context instead.
4. Compare its state with `git status --short`, `git log --oneline -5`, and the
   current branch. Report discrepancies before continuing.
5. Briefly state the note read, its purpose, remaining tasks, and any state
   mismatch. Then start the first remaining task unless it needs a new user
   decision.

When all tasks are complete, propose updating the note's checkboxes; do not
change them without the user's approval.
