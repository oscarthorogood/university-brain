# Vault Index

Entry point for this vault. Read this first to orient, then `Agents/Shared Agents/AGENTS.md` for the rules.

**Second Brain** — University of Edinburgh business & economics coursework, Obsidian, strict template-driven. 486 notes, 17 courses, 7 note types. Internship applications moved to the separate **Internships** vault (`iCloud Drive/Internships`) on 2026-09-30. Counts verified 2026-09-30 with `Agents/Shared Agents/verify-vault.py` (re-run it for live numbers).

---

## Where things are

Note folders sit under `Items/` (work), `Files/` (Zotero, Resources, OneDrive, Summaries, Past Papers, Mind Maps, Research) and `Apps/` (MCQ, Flashcards, Glossary, Podcast). In the app, an Items note's page shows its links as **Related** (what it relates to in `Apps/` and `Files/`) and **Links to** (other Items notes); see `AGENTS.md` §3.4. Wikilinks keep the short form, e.g. `[[Lectures/Some Note]]`.

| Path | What it holds | Count | View |
|---|---|---|---|
| `Courses/` | Course hub notes — everything links back here | 17 | `Courses.base` |
| `Items/Lectures/` | One per lecture, numbered `L{NN}` per course | 181 | `Lectures.base` |
| `Items/Readings/` | Set readings and external research sources | 149 | `Readings.base` |
| `Items/Tutorials/` | Tutorials, seminars and problem sets, numbered `T{NN}` | 79 | `Tutorials.base` |
| `Apps/MCQ/` | Multiple-choice question sets (MCQ tests and quizzes) | 23 | `MCQ.base` |
| `Apps/Flashcards/` | Decks of flip cards | 1 | `Flashcards.base` |
| `Files/Past Papers/` | Past papers and exams, with answers | 9 | `Past Papers.base` |
| `Files/Summaries/` | One-page summaries, formula sheets and cheat sheets | 3 | `Summaries.base` |
| `Files/Mind Maps/` | Concept maps | 0 | `Mind Maps.base` |
| `Apps/Glossary/` | Terms and definitions | 0 | `Glossary.base` |
| `Apps/Podcast/` | Podcast episodes with transcripts | 0 | `Podcast.base` |
| `Files/Research/` | Sourced research briefs, one per question (Researcher) | 0 | `Research.base` |
| `Items/Projects/` | Coursework and personal projects (incl. group deliverables) | 14 | `Projects.base` |
| `Items/Essays/` | Essays and individual written assignments | 12 | `Essays.base` |
| `Items/Exams/` | Exam notes | 0 | — |
| `Items/Assignments/` | One per assignment or hand-in (replaced `TaskNotes/Tasks/`) | 0 | — |
| `Files/Zotero/` | One note per Zotero library item (synced by University Brain) | — | — |
| `Templates/Claude/` | The templates Claude fills — these define the schemas. Subfolders `Items/` (7: Lecture, Tutorial, Essay, Projects, Readings, Exam, Assignment), `Files/` (7 + the `Weekly Summary Template.md` draft, not yet wired in) and `Apps/` (4); `Course Template.md` sits at the top | 19 (+1 draft) | — |
| `Templates/Human/` | Templates Oscar fills by hand (Unsorted Notes) | 1 | — |
| `Templates/Guides/` | Naming Conventions, TaskNotes Guide | 2 | — |
| `Unsorted/` | Intake tray for raw captures — cleared daily by a routine | — | — |
| `Agents/` | `Shared Agents/` (agent instructions, this index, decision log, open items, `verify-vault.py`); then `Course Agents/` (`MSOA/`, `Strategy/`, `TEM/`) and `Helper Agents/` (`Sorter/`, `Scribe/`, `Librarian/` (reading lists and notes, `Ellevenread/`), `Planner/` (`Calendar Sync.md`, `Learn.md`), `Tutor/`, `Writer/`, `Researcher/`, `Analyst/`), and `Manager Agent/` (the Manager's instructions file; it sits outside both groups), one folder per agent, each starting with its own instructions file (`{Name} agent.md`) | — | — |
| `Files/Resources/` | Finished reference **files**, by course and type (16 course folders) | — | — |
| `Files/OneDrive/` | Active working **files**, by course and note type (12 course folders) | — | — |

Ignore every dot-directory at the root: the `.*-backup-*` folders, `.trash/` (raw `Notion Import/`, removed duplicates), `.smart-env/`, and app config. See `AGENTS.md` §1.

---

## How it fits together

All seven note folders are **flat**. A note joins a course by linking to it, never by sitting inside it:

```
Courses/Business Economics.md
    ^ course:: [[Business Economics]]
    |
    +-- Items/Lectures/Business Economics L03 - Market Structure.md
    +-- Items/Tutorials/Business Economics T02 - Cost Curves.md
    +-- Items/Readings/Cabral (2017) - Introduction to Industrial Organization.md
    +-- Apps/MCQ/Business Economics - MCQ - Market Structure.md
```

Each note also carries `base: "[[{Folder}.base]]"`, which puts it in the folder's table view.

---

## Courses

**Year One** — Accountancy 1A (S1) · Digital Skills (S1) · Economic Principles (S1) · Global Business (S1) · Global Challenges (S1) · Economic Applications (S2) · Planning for a Startup (S2) · The Business of Edinburgh (S2)

**Year Two** — Business Economics (S1) · Business Research Methods One (S1) · Globalisation and Trade (S1) · Business Research Methods 2 (S2) · Fundamentals of Programming (S2) · Innovation and Enterprise (S2)

**Year Three (current)** — Management Science and Operations Analytics (S1) · Strategic Management (S1) · The Entrepreneurial Manager (S1)

Exact spellings and traps: `AGENTS.md` §6.

---

## Notes vs files

Notes are markdown and live in the seven folders. Actual documents — slides, PDFs, spreadsheets, drafts — live outside and are **linked, never embedded**:

- `Files/Resources/{Course}/{Slides|Documents|Spreadsheets|Data|Images|Media|Code|Archives}/` — lowercase-hyphenated filenames
- `Files/OneDrive/{Course}/{note type}/` — filename mirroring the note title

`Files/Resources/` has no `Digital Skills` folder yet; `Files/OneDrive/` has none for Fundamentals of Programming, Global Business, Management Science and Operations Analytics, Strategic Management, or The Entrepreneurial Manager. Create the folder when the first file needs filing.

---

## Views

Every type folder has the same views in Obsidian Bases (`{Folder}.base`) and make.md: `All` plus one view per course with notes in that folder (Courses: one per year). make.md tab codes are listed in `memory.md`.

## Also in `Agents/`

- `AGENTS.md` — the rules: session protocol, schemas, naming, course registry, what not to touch
- `Agent Roster.md` — every agent's role, responsibilities, what it does on its own and how far it may act
- `memory.md` — decision log; why the vault looks the way it does
- `open-items.md` — known gaps, deliberately unresolved
- `verify-vault.py` — read-only checker: frontmatter vs templates, base links, course names, naming, duplicates
- `CLAUDE.md` — startup checklist that points here
