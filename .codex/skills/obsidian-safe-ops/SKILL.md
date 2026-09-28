---
name: obsidian-safe-ops
description: Safely read, write, search, move, or open files in the user's Obsidian vault through obs.sh. Use for vault, note, or daily-note operations; use the dedicated Obsidian format skills to compose file contents.
---

# Safe Obsidian vault operations

Use `~/.codex/skills/obsidian-safe-ops/scripts/obs.sh` for every vault
operation. Invoke that path directly; do not assign it to a shell variable.

Requires `obsidian` and `jq` in PATH. Reading, writing, and searching work
while Obsidian is closed; app-only operations require it to be running.

`obs.sh` uses filesystem I/O for note contents and search, then verifies writes.
It uses the Obsidian CLI only for operations that require the app. Do not use
raw `obsidian create`, `append`, `prepend`, `daily:append`, or `search` for
note contents.

## Format coordination

This skill owns vault paths and I/O, not file syntax. Before creating or
editing a supported file, apply the matching installed format skill:

- `.md` — `obsidian-markdown`
- `.base` — `obsidian-bases`
- `.canvas` — `json-canvas`

Use the resulting content with `obs.sh write`, `append`, or `prepend`. Do not
duplicate the format rules here. For a request that only explains or transforms
format without accessing the vault, use the format skill alone.

## Commands

Run `~/.codex/skills/obsidian-safe-ops/scripts/obs.sh --help` for the complete
interface. Paths are relative to the vault root; never pass `path=`, absolute
paths, or paths containing `..`.

```sh
# Read and search
~/.codex/skills/obsidian-safe-ops/scripts/obs.sh read "Notes/example.md"
~/.codex/skills/obsidian-safe-ops/scripts/obs.sh search "query" "Notes" 20

# Write verified content. Put nontrivial content in a temporary file first.
~/.codex/skills/obsidian-safe-ops/scripts/obs.sh write "Notes/example.md" /tmp/body.md
~/.codex/skills/obsidian-safe-ops/scripts/obs.sh append "Notes/example.md" /tmp/body.md
```

`read`, `write`, `append`, `prepend`, `search`, `grep`, `ls`, and `lint` do not
require Obsidian to be open. `move`, `trash`, `prop-*`, `open`, and `daily-*`
do. Use `trash` only after the user has approved deletion.

## Operational invariants

- Never put note content in an `obsidian ... content=` argument. It can corrupt
  multibyte content and does not reliably report errors.
- Prefer `obs.sh search` and `grep`; raw Obsidian CLI search can silently return
  no results.
- Treat an `obs.sh` failure as a failed operation. Do not retry mutations unless
  the requested outcome remains unambiguous.
- Create new notes under `Notes/` unless the user specifies another vault path.
