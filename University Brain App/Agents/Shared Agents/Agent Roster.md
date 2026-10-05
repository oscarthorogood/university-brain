# Agent roster

Every agent in University Brain: who they are, what they own, which model they run on, and how they work. Written 2026-10-02. Keep it in step with `AGENTS.md` §14 and each agent's own file.

**The model.** The **Manager** is the only agent that looks for work. For each job it picks a **helper** to do it and the **course agent(s)** to consult first, the helper does the job with no approval, and the Manager checks the result (and undoes it if it fails). Helpers never start anything themselves. Course agents only advise. Oscar can still chat with any agent, and any agent edits his notes when he asks. An agent that can't do a request says so and the Manager hands it to another; when none can, the Manager does it itself, so every task has an agent.

## Who they are

| Agent | Role | Gets jobs from | What it does | Reads | May write | Web | Model and effort |
|---|---|---|---|---|---|---|---|
| **Manager** | Finds work, assigns, consults, reviews | Itself | Scans for the 22 jobs and checks, picks helper and course agent, reviews and undoes failures, budget, morning brief, week ahead. **Last resort: the general agent**, which does any Markdown request no other agent could | The whole vault | Its own folder; note folders when acting as the general agent | No | **On the Mac**: rules, plain code, Apple's on-device model. Claude only when acting as the general agent | Its own glass-walled office in the south-east corner |
| **Sorter** | Intake and filing | Manager | Files Unsorted into Resources, folds raw notes into lectures | Whole vault, Unsorted | One note at a time; the app does the file moves | No | Sonnet, medium | Desk; Unsorted bin and shelves |
| **Scribe** | Lecture and tutorial write-ups | Manager | Writes up from slides and Oscar's own lines | The note, its slides, the template | The one note it is given | No | Sonnet, medium | Desk; Lectures and Tutorials shelves |
| **Librarian** | Readings and citations | Manager | Confirms citations, finds sources, creates missing Reading notes | Readings, linked files | The one Reading note, or the new Reading notes it is told to create | **Yes** | Sonnet, medium | Desk; Readings and Resources shelves |
| **Planner** | Deadlines, briefs, exam plans | Manager | Fills briefs, builds exam revision plans, keeps the deadline picture | Calendar Sync, Learn snapshot, course notes, brief files | The one note, or the one new Summary note (an exam plan, in `Files/Summaries/`) | No | Sonnet, medium | Desk; Tasks, Essays and Projects shelves |
| **Tutor** | Revision and explanations | Manager | MCQ sets, flashcards and explanations | Lecture notes, slides, existing study notes | One new note in `Apps/MCQ/` | No | Sonnet, medium; Haiku for quick explanations | Desk; Revision and Exams shelves |
| **Writer** | Essay and project coach | Manager | Thesis suggestion, outline, evidence plan | Brief, rubric, Oscar's notes, readings, Research briefs | Only the plan sections of the one note | No | **Opus, high** | Desk; Essays and Projects shelves |
| **Researcher** | Evidence and sources | Manager | Sourced briefs in `Files/Research/` | Whole vault and the web | One new note in `Files/Research/` | **Yes** | Sonnet, medium | Desk; Readings, Research, Resources and Essays shelves |
| **Analyst** | Maths and data | Manager | Worked solutions for formative tutorials and workshops, checks of Oscar's own answers; never assessed work | The note, the sheet, Resources | Only the "Solutions check" section of one tutorial note | No | **Sonnet, high, run twice and compared** | Desk; Tutorials, Exams and Resources shelves |
| **MSOA, Strategy, TEM** | Course consultants | Manager | Advise on jobs in their own course; keep a short course briefing; answer questions in chat | That course's notes | Their own folder (the briefing, notes to self) | No | **Haiku, low** when consulted; Haiku or Sonnet in chat | Their own course shelf on the left wall |

## How they behave

| Agent | What the Manager gives it | Approval | Hands off to | Checked by the Manager for |
|---|---|---|---|---|
| **Manager** | Itself: the 22 jobs and checks | None | The helper that owns each job | Everything below |
| **Sorter** | Files in Unsorted | None | Scribe (slides filed, then a write-up) | Moves landed in Resources, nothing outside note folders changed |
| **Scribe** | A delivered class with slides and an empty note | None | Tutor | Oscar's lines kept, headings and frontmatter intact, slide numbers cited |
| **Librarian** | A reading with a source to confirm; a reading due within a week with none; readings a lecture links that have no note | None | Writer | No dead links; new notes well-formed; never an invented citation |
| **Planner** | A blank essay or project brief; an exam with a date | None | Writer (brief in), Tutor | Only the brief sections changed; new note well-formed |
| **Tutor** | The newest written-up lecture of each course with no revision set | None | Oscar | One new note, right name, right `base` |
| **Writer** | An essay or project with the brief in and no outline, due within four weeks | None | Oscar | Nothing outside the plan sections changed; reads as a plan, not submission prose |
| **Researcher** | An essay or project due within three weeks with the brief in and no research (one a day) | None | Librarian (files its sources), Writer | Every finding has a link, every link opens, single-source findings marked |
| **Analyst** | A quantitative tutorial or workshop with no worked solutions, or Oscar's answers to check | None | Oscar | Only "Solutions check" changed; its answers agree with a second independent solution |
| **MSOA, Strategy, TEM** | A consult before a job in their course; a daily briefing refresh; the Monday week-ahead is posted under their name | Not applicable | The helper (advice) | Not applicable |

## The chain

Sorter files slides, then **Scribe** writes up, then **Tutor** makes the revision set. **Planner** fills a brief, **Researcher** gathers what the notes lack, **Librarian** turns the good sources into Readings, and **Writer** plans the outline from the notes, those Readings and the brief. **Analyst** works through a tutorial sheet and later checks Oscar's answers. Each step starts a few seconds after the last finishes, as long as the Claude plan has room.

## For every agent

- A job edits **only the note it is given** (or adds the one new note it is told to). Permissions enforce this, not just the prompt.
- Every job is an Activity Log entry with who advised, what changed and the review's verdict, and an **Undo** button.
- When Oscar edits what an agent wrote, the agent reads the difference and may add up to three rules to `## Learned from Oscar's edits` in its own file, and reads that section at the start of every job.
- Assessed work (essays, individual case studies, exam content) is never written or solved by an agent: Writer plans, Analyst only works formative material, Researcher only gathers.
