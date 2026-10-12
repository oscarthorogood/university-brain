# Agent roster

There is **one agent: the Manager**. It finds work, takes every request, does it and has it checked. The names below are the **kinds of work** (modes) it does: each one sets the model and effort, whether the web is allowed, the daily limit and the checks, and has a `## Mode: {Name}` section in `Agents/Manager Agent/Manager agent.md`. Written 2026-10-12; keep it in step with `AGENTS.md` §14 and the Manager's file.

**The model.** Looking for work, routing and checking run on Oscar's Mac (rules, plain code and Apple's on-device model); the work runs on Claude Code. For each job the Manager sets the kind of work, reads the course's `Course briefing.md` (there is no one to consult), does the job with no approval, and checks the result (and undoes it if it fails). In chat there is one conversation and one Claude session; a request that is no particular kind of work is handled as general help.

## Kinds of work

| Mode | What it does | Reads | May write | Web | Model and effort |
|---|---|---|---|---|---|
| **General** | Any Markdown request that fits no kind of work: create, edit, rewrite, restructure, merge, split, convert, fix links; proposes `MOVE:` lines for renames | Whole vault | The note folders (after a snapshot), its own folder | No | Sonnet, medium |
| **Sorter** | Intake and filing: files Unsorted into Resources, folds raw notes into lectures | Whole vault, Unsorted | One note at a time; the app does the file moves | No | Sonnet, medium |
| **Scribe** | Lecture and tutorial write-ups from slides and Oscar's own lines | The note, its slides, the template | The one note it is given | No | Sonnet, medium |
| **Librarian** | Readings and citations: confirms citations, finds sources, creates missing Reading notes | Readings, linked files | The one Reading note, or the new Reading notes it is told to create | **Yes** | Sonnet, medium |
| **Planner** | Deadlines, briefs, exam plans | Calendar Sync, Learn snapshot, course notes, brief files | The one note, or the one new Summary note (an exam plan) | No | Sonnet, medium |
| **Tutor** | Revision and explanations: MCQ sets, flashcards, glossaries, podcasts | Lecture notes, slides, existing study notes | One new note in the study folder | No | Sonnet, medium; Haiku for quick explanations |
| **Writer** | Essay and project coaching: thesis suggestion, outline, evidence plan | Brief, rubric, Oscar's notes, readings, Research briefs | Only the plan sections of the one note | No | **Opus, high** |
| **Researcher** | Evidence and sources: sourced briefs in `Files/Research/` | Whole vault and the web | One new note in `Files/Research/` | **Yes** | Sonnet, medium |
| **Analyst** | Maths and data: worked solutions for formative tutorials and workshops, checks of Oscar's own answers; never assessed work | The note, the sheet, Resources | Only the "Solutions check" section of one tutorial note | No | **Sonnet, high** |

Course briefings (MSOA, Strategy, TEM) are written by the app once a day on Haiku into `Agents/Course Agents/{Course}/Course briefing.md`; they are not agents.

## How the kinds of work behave

| Mode | What the Manager gives it | Approval | Often followed by | Checked for |
|---|---|---|---|---|
| **Sorter** | Files in Unsorted | None | Scribe (slides filed, then a write-up) | Moves landed in Resources, nothing outside note folders changed |
| **Scribe** | A delivered class with slides and an empty note | None | Tutor | Oscar's lines kept, headings and frontmatter intact, slide numbers cited |
| **Librarian** | A reading with a source to confirm; a reading due within a week with none; readings a lecture links that have no note | None | Writer | No dead links; new notes well-formed; never an invented citation |
| **Planner** | A blank essay or project brief; an exam with a date | None | Writer (brief in), Tutor | Only the brief sections changed; new note well-formed |
| **Tutor** | The newest written-up lecture of each course with no revision set | None | Oscar | One new note, right name, right `base` |
| **Writer** | An essay or project with the brief in and no outline, due within four weeks | None | Oscar | Nothing outside the plan sections changed; reads as a plan, not submission prose |
| **Researcher** | An essay or project due within three weeks with the brief in and no research (one a day) | None | Librarian (files its sources), Writer | Every finding has a link, every link opens, single-source findings marked |
| **Analyst** | A quantitative tutorial or workshop with no worked solutions, or Oscar's answers to check | None | Oscar | Only "Solutions check" changed; its answers agree with a second independent solution |

## The chain

Sorter files slides, then **Scribe** writes up, then **Tutor** makes the revision set. **Planner** fills a brief, **Researcher** gathers what the notes lack, **Librarian** turns the good sources into Readings, and **Writer** plans the outline from the notes. Each starts a few seconds after the last one finishes. Assessed work is never written or solved.

## For every kind of work

- A job edits **only the note it is given** (or adds the one new note it is told to). Permissions enforce this, not just the prompt.
- Every job is an Activity Log entry with what changed and the review's verdict, and an **Undo** button.
- When Oscar edits what the Manager wrote, it reads the difference and may add up to three rules to its kind of work's section in `Learned rules.md`, and reads that section at the start of every job.
- Daily limits per kind of work (Writer 5, Researcher 5, Analyst 10, Sorter 20, others 30); three failed reviews in a row pause that kind of work for a day.
- Assessed work (essays, individual case studies, exam content) is never written or solved: Writer plans, Analyst only works formative material, Researcher only gathers.
