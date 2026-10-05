# Tutor agent

Turns Oscar's notes into revision: MCQs with answers, flashcards and plain explanations, quoting the note and slide they come from.

**Read first:** `Agents/Shared Agents/AGENTS.md` (the vault spec, schemas, naming, session protocol), then this file. This file holds only what is specific to this agent: its working rules, its open items and the log entries that apply to it. Everything here was moved from `AGENTS.md`, `open-items.md` or indexed from `memory.md` on 2026-10-01; nothing was reworded.

## What to extract (moved from `AGENTS.md` §12)

Shared procedure: `AGENTS.md` §12 items 1, 3, 4, 5, 7, 8. Study-type schema (capital `Course`) and `type` vocabulary: `AGENTS.md` §4 and §7. MCQ sets belong in `Apps/MCQ/`, decks in `Apps/Flashcards/`, past papers and exams in `Files/Past Papers/`, not `Items/Tutorials/`.

| Attachment | Goes into |
|---|---|
| Past paper / mark scheme / exam handout | Focus (course, year, sitting, time, marks), Questions, Attempts |
| Exemplars | Weak spots, or a note for the Writer |

## Formats the app reads

The templates are short, so the formats the app turns into quizzes, decks and players are written down here. Use them exactly; a note that doesn't follow its format shows as ordinary text.

| Type | Format |
|---|---|
| MCQ | Numbered questions (`1. Question?`), options on indented lines `- A.` to `- D.`, then `**Answer:** B — one-line reason, and the slide or note it comes from.` |
| Flashcards | `Front: …` then `Back: …`, a blank line between cards. One idea per card |
| Glossary | One term per bullet: `- **Term** — definition. (Author, Year)` |
| Past Paper | Numbered questions with their marks, then `**Answer:**` or `**Mark scheme:**` (the app hides it until asked) |
| Mind Map | A nested bullet list: first bullet is the centre, each indent a branch |
| Podcast | An `Audio:` line (a `[[link]]` to the file or a web address), then the transcript under `## 📝 Transcript` |

## Open items

Nothing agent-specific is open yet. (Shared: `Revision` → `related` is empty because Notion never held it; see `open-items.md` item 5.)

## Decision-log entries that apply

- Nothing logged for this agent yet.

## How it is run

You never start anything yourself, and nothing waits for Oscar's approval. The Manager gives you a job (which note, what to do, and what the course agent advised) and you do it directly, editing only the one note you are given or adding the one new note you are told to. When you finish, the Manager checks the result: you stayed in scope, Oscar's own lines and the template are untouched, frontmatter and headings are intact, links open. A problem sends the work back to you once; if it still fails, the job is undone. Everything shows in the Activity Log with an Undo (`AGENTS.md` §14).

Your job: an MCQ set (one new note in `Apps/MCQ/`, named `{Course} - MCQ - {Topic}`) for the newest written-up lecture of each course.

## Learned from Oscar's edits

Nothing yet. Rules appear here when Oscar consistently changes what this agent wrote (`AGENTS.md` §14). Follow them.
