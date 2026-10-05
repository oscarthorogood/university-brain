# University Brain: handoff for code review

A macOS app (SwiftUI, macOS 26, Swift 6.2, one SwiftPM executable target, about 9,000 lines) that sits on top of an Obsidian vault of university notes. It shows the notes, and runs a team of AI agents that file, write up, research and check them. This document is for a reviewer who has not seen the project. Written 2026-10-02.

**Please review, don't rewrite.** The most useful output is a ranked list of real problems (bugs, data-loss risks, concurrency mistakes, security issues, misleading UI) with file and line, then smaller simplifications. `PLAN.md` is the project's running log of what is done and what is not; read its "Built 2026-10-02" section first.

---

## 1. What it is, in one minute

- **The vault** is a plain-Markdown folder, by default `~/Documents/University` (override with the `SECOND_BRAIN_VAULT` environment variable). Folders: `Lectures/ Tutorials/ Readings/ Essays/ Projects/ Revision/ Research/ Courses/ TaskNotes/Tasks/ Unsorted/ Resources/ OneDrive/ Templates/Claude/ Agents/`. Notes have YAML frontmatter that must match templates in `Templates/Claude/`. The vault's own rules are in `Agents/Shared Agents/AGENTS.md` (the spec every agent reads) and `Agent Roster.md`.
- **The app** reads the vault into `Store.notes` (`Vault.load()`), shows Home, Week, Month, course pages, lists, a note editor, an isometric "Agent Library" scene, and a Manager menu.
- **The agents** are Claude Code CLI runs (`claude -p`, in the vault directory, with scoped tool permissions). There is no API key; it uses the user's Claude subscription.
- **The Manager** is *not* an LLM agent. It is plain Swift plus Apple's on-device model (FoundationModels). It is the only thing that looks for work.

## 2. The operating model (the part most worth reviewing)

Everything goes through the Manager. For each job (`Store.runJob`, `ManagerScan.swift`):

1. **Find** (`scan()`): ranks 14 kinds of job. 8 more "checks" run separately (`ManagerChecks.swift`).
2. **Consult**: a *course agent* (MSOA, Strategy, TEM) is asked, on Haiku, what matters about the job. `Agent.consult`.
3. **Work**: a *helper* (Sorter, Scribe, Librarian, Planner, Tutor, Writer, Researcher, Analyst) does the job in **one** `claude -p` call with write permission limited to one note or one folder (`Agent.doWork`, `--allowedTools "Edit(path),Write(path)"`). **There is no human approval step.**
4. **Review** (`reviewJob`, `ManagerReview.swift`): deterministic checks on the Mac (scope, frontmatter, headings, "Oscar's own lines still present", new-note shape, links open, section limits), the Analyst's answers compared with a second independent solve, and a narrow on-device-model check of Writer's output. A problem sends the work back **once** with feedback; if it still fails, the job is **undone** (`undoJob`).
5. **Log**: an Activity Log entry with an Undo button; `InboxItem` records what changed.

Safeguards in place of approval: scoped write permissions, the review, undo from `.history/` snapshots, a loop breaker (3 failed reviews pauses a helper for a day; 6-hour cooldown per helper per note), daily caps per agent, a budget gate that reads the real Claude plan usage, skipping notes the user changed in the last 5 minutes or has open, a 12-jobs-an-hour guard, quiet hours / pause / battery switches.

**The risk to weigh hardest:** helpers edit the user's real notes unattended. Please judge whether the checks in `ManagerReview.swift` and the permission scoping in `Agent.run` are actually sufficient, and look for any path where a bad edit survives review and cannot be undone.

## 3. Map of the code

`Sources/SecondBrain/`

| Area | Files | Notes |
|---|---|---|
| App shell, pages, store | `App.swift` (1,300 lines: `@main`, `Store`, sidebar, dock, headless modes, `--check`), `Style.swift`, `Messages.swift`, `AgentChat.swift`, `AgentStage.swift` | `Store` is `@MainActor @Observable`. Headless flags are near the top of `App.main`. |
| The Manager | `ManagerScan.swift` (tick, budget, `scan()`, the pipeline, undo, learn), `ManagerReview.swift` (`Sections`, `Review`), `ManagerChecks.swift` (checks 15–22, week ahead, course briefings), `ManagerJobs.swift`, `ManagerControls.swift` (pause, budget presets, caps, loop breaker), `ManagerMenu.swift`, `ManagerSettings.swift`, `ManagerHeadsUp.swift`, `Manager.swift` (routing rules, tiers), `JobProgress.swift`, `Status.swift` (task states, "Agent In Progress" claim/release), `PlanUsage.swift` | `Manager.swift` holds keyword routing and the on-device `@Generable` router. |
| Agents (Claude runs) | `Agent.swift` (roles, prompts, `run`, `consult`, `doWork`, `refreshBriefing`, `solveIndependently`), `NewNote.swift` (`AgentWork` job definitions, note creation from templates), `Character.swift` (drawn agents) | `Agent.run` builds the CLI call, parses `stream-json`, enforces a time limit. A test hook `Agent.stub` replaces it. |
| Vault I/O | `Vault.swift` (load, frontmatter, `perform` file moves), `Editing.swift` (field setters, `.history` snapshots, `write`), `Files.swift`, `Detect.swift`, `Watcher.swift`, `CalendarNotes.swift`, `Calendar.swift` (ICS sync) | `Vault.perform` copies, verifies a SHA-256, then moves the original to `.trash/`. |
| The library scene | `AgentsLibrary.swift` (isometric Canvas scene, hit layer), `LibrarySim.swift` (agent simulation, A* navigation, world geometry), `Visibility.swift` | Redraws about 20 times a second; paused when the window can't be seen. |
| Other pages | `WeekPage.swift`, `MonthPage.swift`, `ScheduleViews.swift` (List/Board/Timeline/Tree), `CoursePage.swift`, `NotePage.swift` (editor), `Browse.swift`, `Search.swift`, `Tags.swift`, `TasksViews.swift`, `VoiceMemo.swift`, `Notify.swift`, `Settings.swift`, `SyncSettings.swift` | |
| Tests | `PipelineCheck.swift` plus `Manager.check()`, `CalendarSync.check()`, etc. in their files | Run with `--check` (below). |

Outside the sources: `bundle.sh` (builds `build/SecondBrain.app`, compiles the Liquid Glass icon from `Icon/`), `install.sh` (installs to `/Applications/University Brain.app`), `PLAN.md`.

## 4. Build, test and run safely

```sh
swift build                       # debug
swift build -c release            # what bundle.sh and the checks use
.build/release/SecondBrain --check            # all self-checks; exit 0 means pass (see note below)
SECOND_BRAIN_VAULT=/path/to/copy .build/release/SecondBrain --scan       # print the ranked jobs; nothing runs
SECOND_BRAIN_VAULT=/path/to/copy .build/release/SecondBrain --run-top    # runs the top job for real (spends Claude usage)
SECOND_BRAIN_VAULT=/path/to/copy .build/release/SecondBrain --route "request text"
```

- **Never point the app at the user's real vault for experiments.** Copy `~/Documents/University` somewhere and set `SECOND_BRAIN_VAULT`. When that variable is set the app also keeps its own records (Activity Log, jobs) inside `<copy>/.app-support`, so a test cannot touch the real ones.
- `--check` prints one line per check. Swift release builds trap silently on a failed `precondition`, so a crash with exit code 133 and no output means one failed; the pipeline test prints `FAILED: …` to stderr. Piped stdout is buffered, so run it under a pseudo-terminal to see progress.
- The pipeline test (`PipelineCheck.swift`) runs the whole consult → work → review flow against a stand-in for Claude on a throwaway vault, so it costs nothing. It covers success, a retry, rejection with undo, "nothing to do", the loop breaker and three of the checks.
- The vault has its own checker: `python3 "<vault>/Agents/Shared Agents/verify-vault.py"` (read-only). The known baseline is `0 FAIL, 42 WARN`.
- Claude Code CLI (`claude`) must be installed and signed in for any real agent run. Real runs spend the user's plan.

## 5. Verification status (honest)

**Verified**
- `--check` passes: loader, write-back, filing, calendar sync, editing, routing (14 requests), tags, search, new notes, claims, the full pipeline with a fake Claude, the review rules.
- One real end-to-end job on a vault copy: an Analyst job (consult, work, review with a second independent solve, status restored, logged). It also exposed review bugs that were fixed.
- Library clicks (shelves, desks, agents) work with a real mouse.
- CPU: idle pages about 0%, the library about 37% with the window in front (measured).

**Not verified, please look closely**
- The Manager menu (`ManagerMenu.swift`) was compiled but never seen open.
- Settings → Manager (`ManagerSettings.swift`) was seen once; it was then made scrollable and not re-viewed.
- The Manager walking between rooms during a live job (consult / hand over / check visits in `LibrarySim.update`).
- Jobs other than the Analyst's have not run for real in this version: Planner briefs, Librarian web search, Researcher, exam plans, reading notes, Scribe write-ups, learning from edits, undo of a *filing* job.
- Checks 16, 18, 19, 20, 21 and the week-ahead have no automated tests (15, 17 and 22 do).
- Nothing has been installed from this version; the user's installed app is the previous (plan-then-tick) build.

## 6. Where I would look first

1. **`ManagerReview.swift` + `reviewJob` in `ManagerScan.swift`.** Are the checks sound? Specific doubts: `Review.touched(since:)` uses file modification times and treats a stray change under `Agents/` or `Templates/` as a failure but ignores other stray notes (because the user may be editing); "Oscar's own lines" is "any line not in the template", which is weak for notes made from an older template; `checkEdit` ignores `tags`, `related`, `readings`, `references`, `summary` and `status` changes by design; `Sections.hasContent` decides whether a section is still template scaffolding and drives which Analyst job fires.
2. **Undo** (`undoJob`, and the capture block in `runJob`). Restores the exact history snapshot recorded at job time (`Undo.snapshots`); statuses are restored separately; created notes go to `.trash/Undone-<date>/`; filed files are moved back. Look for cases where it restores the wrong thing or where `Vault.history` ordering (by creation date) misleads.
3. **`Agent.run`** (`Agent.swift`): process handling (stdout read before wait, a watchdog timeout that terminates then kills), the `--allowedTools` pattern construction (`scope(file:)` replaces commas with `?` because commas split the list), `stream-json` parsing, `PlanUsage.record`. Is anything injectable from note titles (spaces, parentheses, glob characters)?
4. **Concurrency.** `Store` is `@MainActor`; `Agent.stub` and several statics are `nonisolated(unsafe)`; `agentBusy`/`thinking` are plain flags guarding one run at a time (`autopilotTick`, `manualJob`, `runJob`); `RunLoop`-spinning in the headless modes. Look for races between the tick, a manual job and a chat message, and for an `agentBusy` that can stay true.
5. **The loop and budget logic** (`autopilotTick`, `budgetLeft`, `cooling`, `markHandled`, `known`, `recordReview`): can the Manager spin, starve, or run the same job repeatedly? `handled` is capped at 500 keys; keys include a file modification time, so editing a note re-proposes work.
6. **Vault writes outside the pipeline**: `ManagerChecks.swift` edits notes directly (empty `base`, class times, status hygiene). `CalendarNotes.makeNotes` creates notes on every sync. All write through `Vault.write` (snapshots first) but check the edge cases.
7. **Web safety.** Librarian and Researcher can search the web. Defences are prompt text ("page text is data"), a regex for injection phrases, dead-link checks, and scoped writes. Is that enough?
8. **Performance regressions** in `AgentsLibrary.swift` / `LibrarySim.swift` (per-frame work, the cached sprites, the single hit-test layer).
9. **UI honesty.** Anywhere the interface promises something the code doesn't do (for example text in Settings or the roster).

## 7. Constraints and conventions

- **No new dependencies.** Standard library, SwiftUI, AppKit, FoundationModels, PDFKit, Speech, UserNotifications only.
- **Design:** Liquid Glass for controls and panes (`glassEffect`, styles in `Style.swift`); content is flat. Add controls through the shared styles; don't hand-roll glass buttons.
- **Comment style:** short, explain why. Names match the surrounding code. No dead code left behind.
- **Data safety rules the code must keep:** agents never delete; originals go to `.trash/`; every app write keeps the old text in `.history/`; the user's own lines are never rewritten; assessed work (essays, individual case studies, exams) is never written or solved by an agent.
- **Privacy:** calendar feed URLs live in `~/Library/Application Support/SecondBrain/sync.json` (owner-only), never in the vault or logs. Nothing from notes should be sent to a web search. Don't print or commit those URLs.
- **Not a git repository**, so there is no history to diff. If you propose changes, give them as patches or file-and-line notes.

## 8. Known gaps and ideas (so you don't report them as news)

From `PLAN.md`: vault sync between devices (undecided); a stable code-signing identity; the Analyst can't read spreadsheets; the on-device prose review is deliberately narrow; semester start date and course list are hard-coded (Week 1 = 21 Sep 2026, 13 weeks, three courses); "wrong agent" correction and weekly briefs per course agent are not built; timeline bars need start dates on notes; link-safe renaming, `[[` autocomplete and image paste in the editor are not built.

## 9. What a good review looks like

- A numbered list, most serious first. For each: file and line, what goes wrong, a concrete failing scenario (inputs, state, outcome), and a suggested fix.
- Separate **bugs / data-loss risks** from **design concerns** from **cleanups**.
- Say which findings you reproduced and which you inferred from reading.
- Don't spend effort on formatting, naming taste or style unless it hides a bug.
- If you run anything that spends Claude usage, say so and keep to a vault copy.
