# Manager agent

The only agent that looks for work, and the one everything goes through. It finds a job, picks the helper to do it and the course agent(s) to consult, hands it over, and checks the result. It runs **entirely on Oscar's Mac** (rules, plain code and Apple's on-device model; no Claude), so it costs nothing and nothing it reads leaves the machine. Written 2026-10-02 (University Brain).

**Read first:** `Agents/Shared Agents/AGENTS.md` (§14 is the operating model), then this file. The Manager runs inside the app, not as a Claude Code session, so this file is its written spec for anyone (or any agent) who needs to know what it does.

## The pipeline for every job

1. **Find.** It scans when the app opens, whenever the vault changes, and every few minutes (list below), ranks the jobs and takes the best one that is allowed now.
2. **Choose.** It picks the helper for the job and, if the job belongs to a course, the course agent(s) to consult.
3. **Consult.** It asks the course agent (Haiku, quick) what matters about this job in that course: dates, weights, what the lecturer emphasises, mistakes to avoid. The course agent reads its own `Course briefing.md` first, so this is cheap. The advice goes into the helper's brief.
4. **Hand over.** The helper does the job directly. **No plan to approve and no tick, for any helper, including Writer.**
5. **Check.** When the helper finishes, the Manager reviews the result (below). A problem sends the work back **once** with what was wrong. If it still fails the review, the job is **undone** and logged. Nothing ever waits for Oscar.
6. **Log.** Every job is an Activity Log entry with who advised, what changed and what the review decided, with an **Undo** button.

## What the review checks (on the Mac)

- Only the permitted note changed (or exactly one new note, in the right folder), and nothing in `Agents/` or `Templates/`.
- The frontmatter is intact (`course`, `base`, dates and numbers unchanged), no section was removed, and the sections a job may not change are word-for-word the same.
- **Oscar's own lines are all still there** (any line that isn't template text).
- A new note has every key from its template, the right `base`, a real course and the right title pattern.
- Research briefs: every finding has a link, and every link opens. Librarian and Researcher: no links that are dead.
- Nothing that reads like instructions aimed at an AI (a sign of text copied from a web page).
- Analyst: its answers are compared in code with a second, independent solution; they must agree to within 1%.
- Writer: the on-device model checks, one section at a time, that it wrote a plan and not finished prose.

## What it looks for (22)

*Jobs:* 1 Unsorted files → Sorter (100) · 2 blank essay or project brief → Planner (85 minus days to the deadline) · 3 missing outside research, at most one a day → Researcher (82 minus days) · 4 essay or project with no outline → Writer (80 minus days) · 5 quantitative tutorial or workshop with no worked solutions → Analyst (60) · 6 class not written up → Scribe (50) · 7 reading with no source, due within a week → Librarian (45) · 8 readings an upcoming lecture links that have no note → Librarian (40) · 9 an exam date appears → Planner (70) · 10 lecture with no revision set → Tutor (30) · 11 citation to confirm → Librarian (20) · 12 Oscar's own tutorial answers to check → Analyst (55) · 13 week ahead per course, Monday morning (from plain facts, posted under each course agent) · 14 Oscar's edits to agent work, to learn from → that agent (10). Anything due within three days jumps the queue (+30).

*Checks (free, on the Mac; a helper is called only when one finds a problem):* 15 vault health (fixes an empty or wrong `base`; reports the rest) · 16 broken wikilinks and missing attached files · 17 calendar drift (a class's time differs from its note: the note is corrected) · 18 deadline consistency against Calendar Sync · 19 at-risk deadlines (due within 3 days and not started, or overdue and open) · 20 missing slides for a class within 24 hours · 21 quality sweep (finished work that still looks unfinished goes back to the helper) · 22 status hygiene (written-up classes that have happened become Done).

Each can be switched off in the **Manager menu** (top right of the Agents page).

## How it decides who gets a request

1. **Keyword rules**, instant and free. 2. **The on-device model** when the rules are unsure. 3. **Fallback**: the closest rule match, then the course agent if a course is named, then Planner. Chat requests only need to go to an agent; the answer comes from that agent.

## Limits and safeguards

- **Budget.** It reads the real Claude plan usage. Background jobs start only below the budget preset: Cautious 50%, Balanced 60% (default), Generous 75% of the 5-hour window, with the week at 60 / 70 / 85%; Opus jobs below 30 / 40 / 55%. A runaway guard of 12 jobs an hour always applies, and a Claude usage limit pauses it for an hour.
- **Daily caps per agent** (Writer 3, Researcher 3, Analyst 6, Sorter 12, others 20).
- **Loop breaker.** The same helper isn't put on the same note again for six hours; three failed reviews in a row pause that helper for a day.
- **Leave it alone.** A note Oscar changed in the last five minutes, or has open, is skipped.
- **Pause, quiet hours, battery.** From the Manager menu: pause (an hour, four hours, until tomorrow), quiet hours, pause on battery or in Low Power Mode. The calendar sync carries on.
- **Chat first.** If Oscar is chatting with an agent, queued jobs wait.

## Effort tiers

| Tier | Model and effort | Used for |
|---|---|---|
| quick | Haiku, low | Course-agent consults and briefings, short lookups |
| standard | Sonnet, medium | Sorter, Scribe, Librarian, Planner, Tutor, Researcher |
| careful | Sonnet, high | Analyst (run twice and compared) |
| deep | Opus, high | Writer |

## Rules

- One helper per background job, with course agents only as advisers. No fan-out.
- **Teams in chat (2026-10-03).** A chat request can go through up to three agents in order when one needs what the other produces (Librarian → Tutor, Researcher → Writer, Analyst → Tutor, Planner → Writer), or when Oscar names two agents. The course agent advises first (its briefing is refreshed if it was last written before today). Each stage receives the earlier output and ends with a `Handoff` section; the last stage produces the result, and a different agent then checks it against the handoff and flags anything unsupported. Every chat and job prompt also carries the date, the teaching week and the team's last ten Activity Log entries.
- Chat never edits notes. A job lets a helper edit one note, or add one new note. Files move only through the app (copy, check, original to `.trash/`); nothing is deleted.

## Open items

Nothing agent-specific is open yet.

## Decision-log entries that apply

- 2026-10-02 — the Manager-centred model: helpers no longer wait for approval; course agents consult; the Manager reviews (see `memory.md`).

## Learned from Oscar's edits

Nothing yet (`AGENTS.md` §14).
