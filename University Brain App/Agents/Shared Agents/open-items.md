# Open items

Known gaps, deliberately unresolved. **These are not bugs — do not "fix" them without asking.** They are recorded so no session wastes effort rediscovering them. Last reconciled 2026-09-30 against `verify-vault.py` (0 FAIL, 42 WARN after the 2026-09-30 course fill — the WARNs are items 1–3 and 5 below).

---

## 4. ~~One broken link in a note~~ — fixed 2026-09-30

`Innovation and Enterprise L11 - Business Models` now links `[[Osterwalder et al. (2014) - Value Proposition Design]]`.

## Moved to the agents' own files (2026-10-01)

Open items that belong to one agent now live in that agent's file, so each agent finds its own gaps without reading the rest:

- **Librarian** — the Readings gaps (`To Find`, readings with no `course`, readings that break the naming convention).
- **Scribe** — template backfill, lecture restyle and undelivered lectures.
- **Sorter** — file-store coverage gaps, the exposed credentials in `Unsorted/`, the recurring slide PDFs.
- **Planner** — the `Upload Lecture Slides` task.
- **Strategy** and **TEM** course agents — the date and file questions that belong to one course.

Shared items (5, 7, 8, 10, 12, 13 and the year/semester question) stay below.

---

## 5. Fields empty because Notion never held the data

Not recoverable from the import. Fill in by hand as the material is used: `Revision` → `related`; `Tutorials` → `readings`; `Essays` and `Projects` → `summary`.

---

## 7. Setup not yet done

- **Obsidian `userIgnoreFilters`** — `.obsidian/app.json` has no filter. Add the dot-directories and `Unsorted/`-style intake paths you want excluded (see `AGENTS.md` §1) via Settings → Files & Links → Excluded files.
- **No `CLAUDE.md` / `AGENTS.md` at the vault root.** They live in `Agents/`, so tools that only auto-load from the root won't see them. Claude sessions are covered by the Second Brain project instruction ("read admin first"). Ask Oscar before adding root pointer stubs (they were removed on purpose on 2026-09-23).
- **make.md views missing MSOA in two folders** (re-checked 2026-09-30): `Items/Tutorials/.space/views.mdb` (has All + ACC…I&E, SM, TEM) and `Items/Readings/.space/views.mdb` (has All, ACC, EP, GB, BE, BRM1, G&T, SM; one MSOA reading now exists; also now needs BRM2, I&E and PfaS views — added to `Readings.base` 2026-09-30). Both `.base` files already have the view. Add the MSOA view (filter `course` isLink `Management Science and Operations Analytics`, same columns as the others) with Obsidian closed, per `memory.md` 2026-09-23. `Items/Readings/.space/views.mdb` also still lacks the Due column. Every other folder's make.md views match the courses present.

## 8. Missing admin folders

`Admin/App/` (companion app spec, dashboard image) and `Admin/Archive/` (an AGENTS pointer stub, an old BRAT log) are recorded in `memory.md` (2026-09-23) but do not exist, and no copy is in the vault, `.trash/` or any backup. Likely lost to OneDrive sync. Oscar can check OneDrive's version history / recycle bin. make.md and Obsidian's workspace still remember those paths (harmless). Don't recreate empty folders.

## 10. Backup directories still present

All dot-directories at the vault root (see `AGENTS.md` §1) are backups or trash. Safe to delete once the current state is trusted, but that is Oscar's call — an agent must never remove them. (`.migration-backup-path.txt` is no longer in the root, checked 2026-09-30.)

---

## Needs Oscar's confirmation

- Year/semester for the three Year Three courses were inferred from calendar dates.

## 12. All backup/trash dot-directories missing from the vault root (2026-09-29)

At the start of this session's run, none of the `.{thing}-backup-YYYYMMDD/` folders listed in `AGENTS.md` §1 were present, and `.trash/` didn't exist either (only `.makemd`, `.obsidian`, `.smart-env`, `.space` were there). This wasn't caused by this session — nothing was deleted by any agent — so it's likely the same OneDrive sync issue that already lost `Admin/App` and `Admin/Archive` (item 8). `.trash/` was recreated this session (as `.trash/Unsorted-cleared-20260929/`) to hold a cleared raw file; the backups themselves are not recoverable from here. Oscar may want to check OneDrive's version history / recycle bin, as suggested for item 8.

**Update 2026-09-30:** the old backups are still gone. Present now: `.trash/` (recreated 2026-09-29), `.unsorted-fold-backup-20260929/`, `.overdue-readings-backup-20260930/`, `.admin-audit-backup-20260930/`.

## 13. Small leftovers found in the 2026-09-30 audit (harmless, left in place)

- `TaskNotes/Views/kanban-default.base.bak` — a backup copy next to the plugin view (Views/ is not ours to edit). Oscar can delete it if the kanban view works.
- `Files/OneDrive/.com.greenworldsoft.syncfolderspro` — a marker file from the Sync Folders Pro app. Harmless unless that app is no longer used.
- `Icon\r` files in several folders are macOS custom-folder-icon files, not notes. Ignore.

