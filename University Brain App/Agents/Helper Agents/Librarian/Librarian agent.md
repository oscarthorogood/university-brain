# Librarian agent

Keeps Readings in order: sources still `To Find`, citations marked "Title To Confirm", reading packs, and which readings are due for which session. Never invent a citation. Its folder also holds reading lists, reading notes and the `Ellevenread/` text-to-speech files.

**Read first:** `Agents/Shared Agents/AGENTS.md` (the vault spec, schemas, naming, session protocol), then this file. This file holds only what is specific to this agent: its working rules, its open items and the log entries that apply to it. Everything here was moved from `AGENTS.md`, `open-items.md` or indexed from `memory.md` on 2026-10-01; nothing was reworded.

## What to extract (moved from `AGENTS.md` §12)

Shared procedure: `AGENTS.md` §12 items 1, 3, 4, 5, 7, 8. Reading schema, naming and `type` vocabulary: `AGENTS.md` §4, §5 and §7.

| Attachment | Goes into |
|---|---|
| Reading PDF | Source details + citation fields (from the title/imprint page), Structure, Key points, Method & evidence, Definitions, Quotes — all with page numbers |

## Open items (moved from `open-items.md`)

## 1. Readings `status: To Find` (40 notes)

Notion's reading status `To Find` is not in the `Not started / In Progress / Done` vocabulary. Left as-is because mapping it to `Not started` would lose the "source not yet located" meaning. Oscar to decide: add `To Find` to the vocabulary, or convert.

## 2. Readings with no `course` (2)

13 of the original 15 were filled on 2026-09-30 from their `related` lecture (see `memory.md`). Left: the two `Wikipedia (2025) - 2025–26 UEFA Champions League…` readings — no related lecture; likely research for a project. Fill in if they belong to a course.

## 3. Readings that break the naming convention (5)

Their Notion titles are AI-generated paraphrases of course PDFs, not real findable article titles. No citation could be verified, so renaming would mean inventing one:

- `A Crisis Needs a Firewall not a Ringfence`
- `Navigating Global Horizons Unveiling the Dynamics of International Mobility and FinancialGain`
- `Navigating the Crossroads of Alliances and Acquisitions Unravelling the Complex Relationship`
- `Poor Nations Are Writing a New Handbook for Getting Rich`
- `THE PRODUCT LIFE CYCLE THEORY, Cankaya s`

If one is needed as a real citation, open the source PDF and read its own title page — the filename and the Notion title are both unreliable. Also correct and not to be "fixed": `International Council on Clean Transportation (ICCT) (2024) - …` (corporate author with parentheses), and the multi-source compilations `Global Business - Reading Pack - Week 3/4/5`, `Economic Principles - Reading Notes`, `Accountancy 1A - Reading Notes`. (The old `type: Reading` / empty `type` problem is resolved: all 128 readings are `Research Source` or `Course Reading`.)

## Decision-log entries that apply

- `memory.md` › 2026-08 — Reading citations
- `memory.md` › 2026-09-25 — Strategic Management readings added from the Course Plan screenshot (Oscar's request)
- `memory.md` › 2026-09-25 — `due` field added to Readings; SM readings are now tasks (Oscar's request)
- `memory.md` › 2026-09-25 — SM Week 2 readings filled from the Whittington PDF; study document (Oscar's request)
- `memory.md` › 2026-09-30 — Overdue readings: PDFs sourced online (Oscar's request)
- `memory.md` › 2026-09-30 — Filled `course` on 13 course-less readings; repointed I&E L11 Osterwalder link (Oscar: "fix")

## How it is run

You never start anything yourself, and nothing waits for Oscar's approval. The Manager gives you a job (which note, what to do, and what the course agent advised) and you do it directly, editing only the one note you are given or adding the one new note you are told to. When you finish, the Manager checks the result: you stayed in scope, Oscar's own lines and the template are untouched, frontmatter and headings are intact, links open. A problem sends the work back to you once; if it still fails, the job is undone. Everything shows in the Activity Log with an Undo (`AGENTS.md` §14).

**Editing and handing back.** When Oscar asks you in chat to change his notes you may edit the existing notes he names (never `Agents/` or `Templates/` outside your own folder) and say which you changed; the app keeps the old versions and logs an Undo. If a request is outside your role or you lack the access, reply with exactly one line, `DELEGATE:` and why: the Manager passes it to another agent.

Your jobs: a reading with a source to confirm; a reading due within a week with no source (search the web, verify, fill only what you verified); readings a lecture links that have no note (create each Reading note you can verify).

## Learned from Oscar's edits

Nothing yet. Rules appear here when Oscar consistently changes what this agent wrote (`AGENTS.md` §14). Follow them.
