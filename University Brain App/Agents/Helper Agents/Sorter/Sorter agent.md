# Sorter agent

Keeps `Unsorted/` clear: files slides and documents into `Files/Resources/{Course}/…`, folds raw lecture notes into their Lecture note, turns links into Readings. Runs as **Sort Now** and **File Now** in the University Brain app, and prepares plans on its own in the app's Agents inbox.

**Read first:** `Agents/Shared Agents/AGENTS.md` (the vault spec, schemas, naming, session protocol), then this file. This file holds only what is specific to this agent: its working rules, its open items and the log entries that apply to it. Everything here was moved from `AGENTS.md`, `open-items.md` or indexed from `memory.md` on 2026-10-01; nothing was reworded.

## How you work

- **Sort Now** (a button in the University Brain app; there is no scheduled sort): the Sorter plans every item in `Unsorted/` and the app moves the files straight away (copy → verify → `.trash`) and you make the note edits. Dedup rule: check whether a note/task for that course+date already exists; a ticked `- [x]` in `Calendar Sync.md` also means "already filed". Tick the box in the same edit that creates its note/task. If the vault folder isn't connected and can't be reached unattended, notify Oscar and stop rather than skipping silently.

In the app the files are moved by the app, not by you: copy → verify → original to `.trash/`, never overwritten, never deleted. You read, plan, and edit or create Markdown notes. See `AGENTS.md` §9 for where files go and §1 for paths not to read.

## Open items (moved from `open-items.md`)

## 9. File-store coverage gaps

- `Files/Resources/` has no `Digital Skills` folder (`The Entrepreneurial Manager` was created 2026-09-29).
- `Files/OneDrive/` has no folder for Fundamentals of Programming, Global Business, Management Science and Operations Analytics, Strategic Management, or The Entrepreneurial Manager.

May simply mean no files exist yet. Create the folder when the first file needs filing.

## 11. Security: exposed API credentials found in `Unsorted/` (2026-09-29)

`Unsorted/creds.txt` (modified 2026-09-28) is not a vault note — it's a pasted RTF fragment containing what looks like a live access-key ID and secret key pair (`AKID=`/`SK=`). This doesn't match the Unsorted Notes Template and isn't lecture material, so it was left untouched rather than filed, deleted, or moved — flagging for Oscar instead. Still there on 2026-09-30. **Update 2026-10-01:** no longer in `Unsorted/`, but a copy still sits in the backup `.unsorted-fold-backup-20260929/Claude-Unsorted/creds.txt` (backups are Oscar's to delete). Rotating the key still applies if it was real. Given it's sitting in a synced folder (now iCloud), worth rotating the key if it's real and moving the file out of the vault.

- Is a raw slide PDF landing in `Unsorted/` (2026-09-25, an MSOA L02 deck) expected to recur or was it a one-off? (Recurred again 2026-09-28 and 2026-09-29 with TEM/MSOA decks — looks like a regular pattern now, not a one-off.)

## Decision-log entries that apply

- `memory.md` › 2026-09-23 — Claude inbox/unsorted tray cleared
- `memory.md` › 2026-09-23 — Admin folder reorganised
- `memory.md` › 2026-09-23 — Daily Claude/ folder sort set up (Oscar's request), first pass run
- `memory.md` › 2026-09-25 — Daily Claude/ folder sort, second pass
- `memory.md` › 2026-09-25 — Admin folder made the single reliable source of truth (Oscar's request)
- `memory.md` › 2026-09-25 — Where Claude deliverables go (Oscar's instruction)
- `memory.md` › 2026-09-28 — Daily Claude/ folder sort, third pass
- `memory.md` › 2026-09-29 — Daily Claude/ folder sort, fourth pass
- `memory.md` › 2026-09-29 — Vault moved from OneDrive to iCloud Drive
- `memory.md` › 2026-09-29 — Daily Claude/ folder sort, fifth pass (Unsorted only)
- `memory.md` › 2026-10-01 — Claude/Unsorted sort, sixth pass (Oscar: "sort through unsorted")
- `memory.md` › 2026-10-01 — Admin/ and Claude/ replaced by Unsorted/, Agents/ and Templates/ (Oscar's request)

## How it is run

You never start anything yourself, and nothing waits for Oscar's approval. The Manager gives you a job (which note, what to do, and what the course agent advised) and you do it directly, editing only the one note you are given or adding the one new note you are told to. When you finish, the Manager checks the result: you stayed in scope, Oscar's own lines and the template are untouched, frontmatter and headings are intact, links open. A problem sends the work back to you once; if it still fails, the job is undone. Everything shows in the Activity Log with an Undo (`AGENTS.md` §14).

Your jobs: files waiting in `Unsorted/`. Read each, plan where it goes, reply with the `MOVE:` lines and which notes to link or update; the app does the moves (copy, check, original to `.trash/`) straight away and you then make the note edits.

## Learned from Oscar's edits

Nothing yet. Rules appear here when Oscar consistently changes what this agent wrote (`AGENTS.md` §14). Follow them.
