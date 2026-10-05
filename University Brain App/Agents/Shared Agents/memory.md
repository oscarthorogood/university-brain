# Decision log

Durable decisions about this vault and the reasoning behind them. Append; do not rewrite history. Each entry: what was decided, why, and how to apply it.

Purpose: these rules are not derivable from the files. Without this log every agent re-litigates them or silently breaks them.

---

## 2026-08 — Template migration

**Frontmatter conforms to templates exactly; no extra fields.**
Why: Oscar chose strict template conformance over keeping convenient extra fields, accepting that the Bases views had to be rewritten to match. Verified at 0 deviations across the vault.
How to apply: copy the template's field set verbatim. Needing a new field means editing the template first, then the `.base`, then backfilling notes.

**`Resources.base` was retired.**
Why: Resources is a file store, not a note type, so it has no rows to show.
How to apply: do not recreate it. Seven `.base` files is correct.

---

## 2026-08 — Notion reconciliation and audit

The vault was audited against `Notion Import/` (6 databases, 430 rows, 469 attachments) and repaired. Backup at `.audit-backup-20260819/`.

**Assessments go in `Revision`, not `Tutorials`.**
Why: MCQ tests and exams are revision material, not tutorial work, even though Notion filed them together.
How to apply: type them `MCQ Test` or `Exam` in `Revision/`.

**Lectures carry `date` for delivery; `due` does not exist on lectures.**
Why: lectures have a delivery date, not a deadline. `due` stays on Tutorials, Essays and Projects.
How to apply: `date` was added to both the Lecture template and `Lectures.base`.

**Lectures are numbered chronologically across the whole course, not per semester.**
Why: a single continuous sequence per course sorts correctly in every view.
How to apply: Semester 1 material takes `L01`+ and later material renumbers behind it. Ordering key is the Notion `Date`, falling back to `Created`.

**Duplicate lecture titles get ` - I` / ` - II` by date.**
Why: merging them would lose distinct sessions.
How to apply: suffix in date order; never merge.

**Course names are canonical and fixed.**
Why: they are link targets; a variant spelling silently orphans a note.
How to apply: Notion's "Inovation" typo is corrected to `Innovation and Enterprise` everywhere. `Digital Skills` and `Global Challenges` are real courses with no Notion equivalent — their absence from the export is expected.

**Trap — verify attachments by content hash, never by filename.**
Why: Notion attachment filenames collide across courses (`Tutorial_7.pdf` and similar). Trusting filenames already caused five attachments to be filed under the wrong course and five to be dropped entirely.
How to apply: hash before matching, always.

---

## 2026-08 — Reading citations

**Real citation data was recovered for 15 of 23 misnamed Readings**, confirmed against the PDFs' own text (chapter titles, page numbers) rather than filenames: Wilkinson *Managerial Economics* 2nd ed. 2013 (Notion mislabelled it "Managerial Strategy"), Besanko et al. *Economics of Strategy* 6th ed. 2013, Baye & Prince *Managerial Economics and Business Strategy* 8th ed. 2013, Cabral *Introduction to Industrial Organization* 2nd ed. 2017, Chesbrough 2020 (Forbes — Notion's title was an AI paraphrase; real headline is "IBM Watson and the Value of Open"), Heading & Cavaciuti-Wishart 2024 (WEF), Laszlo et al. 2020 (*Sustainability*), Osterwalder et al. 2014, Cumming & Johan 2013.

**Multi-source compilations get a course prefix instead of a fabricated author/year.**
Why: they are not single citable works, and forcing `{Author} ({Year})` on them would invent a citation.
How to apply: name them `{Course} - Reading Pack - Week {N}` or `{Course} - Reading Notes`. Existing examples: `Global Business - Reading Pack - Week 3/4/5`, `Economic Principles - Reading Notes`, `Accountancy 1A - Reading Notes`.

---

## 2026-08 — Agent instruction layer

**Agent instructions live in `Admin/Claude/`** (originally `Claude/` with pointer stubs at the vault root).
Why: `CLAUDE.md` and `AGENTS.md` are only auto-loaded from the root, but the content belongs somewhere editable and visible in Obsidian. `AGENTS.md` rather than a Claude-only file because it is the cross-tool standard — Codex, Copilot and Cursor read it too.
How to apply: edit `Admin/Claude/AGENTS.md`.

**Obsidian's `userIgnoreFilters` has NOT been applied yet.** The JSON is documented in `AGENTS.md` §1 for Oscar to apply via Settings → Files & Links → Excluded files.

---

## 2026-09 — Year Three courses added from the Dashboard inbox

**Three Year Three, Semester 1 courses were added:** `Management Science and Operations Analytics`, `Strategic Management`, `The Entrepreneurial Manager`.
Why: calendar events for them arrived in `Claude/inbox/`. Year/semester (`Three` / `Semester 1`) were inferred from the date, not stated by Oscar.
How to apply: seminars have no template of their own, so they are filed as Tutorials (`Strategic Management T01 - Seminar 1`). Where the calendar gives no topic, the title topic is a placeholder (`Lecture N`), matching the existing `Innovation and Enterprise T01 - Tutorial 1` precedent — rename once the real topic is known. Lectures numbered chronologically by delivery date; the calendar's un-numbered first entry is L01.

**Non-course calendar items are not filed as notes.** The Take survey (Entrepreneurial Manager group formation) went into that course's Key dates. The two Edinburgh Award for Employability & Leadership sessions belong to no course and were left in the inbox for Oscar to decide.

---

## 2026-09 — Internships base seeded from Trackr

**163 Summer 2027 internship notes were added to `Internships/` from two pasted Trackr lists (tech/data list and finance/consulting list).**
Why: Oscar asked for the roles relevant to his CV. His profile is Business Management (Edinburgh) with marketing, sales and AI-tool-building experience, so the filter was "Business + AI/product/data" (Oscar's choice). Pure software engineering, quant dev/research, cyber and IT roles were left out.
How to apply: notes follow `Internship Template.md` exactly, titled `{Company} - {Role}` with no year in the title, `status: Not started`, `source: Trackr`, `base: "[[internships.base]]"`. Trackr detail (open/close dates, last year's opening, test providers, Trackr notes) lives in `notes`. `priority`, `location`, `link`, `duration` and `start_date` are deliberately blank — Trackr did not supply them reliably. `rolling` copies Trackr's Rolling flag where it could be read; roles from the tech list default to `false`.
Excluded on purpose: programmes already closed at 2026-09-21, spring weeks/insight days, women-only or diversity-restricted schemes, language-required roles, final-year-only roles, US-citizen-only, PhD-only, and part-time roles.
Not verified: eligibility for each firm (year of study) — check each spec before applying.

---

## 2026-09-23 — Claude inbox/unsorted tray cleared

**First files for Year Three courses filed into `Resources/`.** Created `Resources/Strategic Management/{Slides,Documents,Spreadsheets}/` and `Resources/Management Science and Operations Analytics/{Slides,Documents}/`. Week 1 slides linked from each course's L01 `resources`.

**Course attribution was decided from file content, not filenames.** `Group.pdf` and `Individual .pdf` carry no course name; their deadlines (29 Oct / 03 Dec) match MSOA Coursework 1 and 2 in the MSOA L1 slides, so they are MSOA. The Harvest Provisions / Easy Energy / ConnectEd examples match the Strategic Management individual-report brief (same question style, "Tutorial 03, Group 01") and are SM.
Unverified: `group-work-presentation-rubric.xlsx` (sheet "Video", author J. Viotto da Cruz) was filed under Strategic Management because it arrived with the SM batch — confirm. `uebs-individual-coursework-cover.docx` is a generic UEBS cover sheet, filed under MSOA because both MSOA briefs require it.

**Assessment notes created:** SM Individual Report (Essay, due 2026-12-18), SM Team Project (Project, due unknown), MSOA Group Case Study (Project, CW1, due 2026-10-29), MSOA Individual Case Study (Essay, CW2, due 2026-12-03). Individual written reports go in `Essays/` (precedent: `Business Research Methods One - Essay - Individual Report`); group deliverables go in `Projects/`. Deadlines added to course Key dates.

**Whittington et al. (2020) Exploring Strategy 12th ed.** added as a `Course Reading` for Strategic Management, citation checked against the PDF's title/imprint pages.

**Raw lecture capture folded into its Lecture note.** The unsorted SM lecture-one note (BMW stakeholder analysis) was merged into `Strategic Management L01 - Lecture 1` and the raw note removed, per the Unsorted Notes template.

**The Entrepreneurial Manager L04** created for the 2026-10-14 calendar event, continuing the weekly sequence.

**Non-course calendar items are filed as TaskNotes.** At Oscar's request the two Edinburgh Award for Employability & Leadership intro sessions (same session offered twice) became one task in `TaskNotes/Tasks/`, due the first option's date, listing both options. This supersedes "left in the inbox" in the 2026-09 entry above.

**TaskNotes conventions written up in `Admin/Guides/TaskNotes Guide.md`.** Tasks link to vault notes through `projects` (any note, not just Projects/). `contexts` is limited to `coursework`, `study`, `careers`, `admin`. Titles are verb-first with no dates.
The inline-convert folder was changed from `{{currentNotePath}}` to `TaskNotes/Tasks` at Oscar's request. The old value would have created task files inside the flat note folders.

---

## 2026-09-23 — TaskNotes synced with upcoming vault items

**58 TaskNotes created in `TaskNotes/Tasks/` from every dated item still ahead.**
- Lectures and seminars/tutorials → `Attend {note title}`, `scheduled` = session date+time (from the note's Session details), context `study`, no `due`.
- Coursework → `Complete …` with `due` = deadline and `scheduled` ~2 weeks before (SM Individual Report scheduled the day after questions release). SM Team Project has no date, so a `Confirm … Presentation Date` task sits on Seminar 1. TEM group-formation survey due 2026-10-09 10:00.
- Internships → `Apply to {note title}` for every role with a fixed upcoming `deadline` and `applied` not Yes (Oscar's choice; rolling roles skipped). `scheduled` = 7 days before (3 if closing within 3 weeks, never before today); `priority: high` if closing within 10 days. BlackRock and Rothschild skipped (already applied).
How to apply: re-running a sync should skip titles that already exist in `TaskNotes/Tasks/`.

---

## 2026-09-23 — make.md set up

**make.md runs in "strict" mode so it can never change notes.** At Oscar's request: folder notes off (`enableFolderNote: false`), frontmatter sync off (`saveAllContextToFrontmatter`, `syncFormulaToFrontmatter`, `autoAddContextsToSubtags` all false), Properties panel left visible (`hideFrontmatter: false`). Backup and Notion Import folders are in `skipFolders`.
Why: make.md otherwise writes `sticker`/`color`/context fields into frontmatter and creates `{Folder}/{Folder}.md` notes, which break the template-conformance and flat-folder rules.
How to apply: folder icons and colours live only in `{Folder}/.space/def.json` (`label` + `defaultSticker`, which also gives every note in the folder that icon). Do not turn folder notes back on. Setting an icon on an individual note in make.md writes its `sticker` field — allowed only on types whose template has `sticker` (not Readings or Revision).

**Navigator tabs (waypoints, `.space/waypoints.json`), by area:** University (Courses, Lectures, Tutorials, Readings, Essays, Projects, Revision) · Careers (Internships) · Tasks (TaskNotes) · Files (Resources, OneDrive) · Admin (Admin, Claude) · Vault (whole tree).
Edit make.md's `data.json` only with Obsidian closed — the plugin rewrites it from memory while running.

**Duplicate `Courses/Inovation and Enterprise.md` removed** (moved to `.trash/`, recoverable). Nothing linked to it; the canonical `Innovation and Enterprise` hub stays. Its `status: done` was corrected to `Done`.

**Course-grouped views added (2026-09-23).** Each type base (Lectures, Tutorials, Readings, Essays, Projects, Revision) gained a second view, `By Course`, grouped by `course` (`Course` for Revision). `Courses.base` gained `By Year`. Existing `Table View` stays first/default. No new `.base` files — still seven + internships.

---

## 2026-09-23 — Full audit after legacy notes reappeared

**142 duplicate notes (plus an empty make.md folder note, `Lectures/Lectures.md`) moved to `.trash/Audit 2026-09-23 duplicates/`** (recoverable; `README.md` there lists each removed file and the note it duplicated). They were pre-audit copies — old Notion titles, `Inovation` spellings, per-semester lecture numbers, old schema with `due` on lectures, exams filed in Tutorials — that reappeared around 08:29 on 2026-09-23 (cause unknown; likely sync). Lecture pairs were matched with `.audit-backup-20260819/renameplan.md`; every other pair was checked line by line. None held content missing from the kept note, and nothing linked to them. `Alexander Osterwalder et al et al. (2014)` was merged into `Osterwalder et al. (2014) - Value Proposition Design` (its `related` link carried over).
How to apply: if duplicates appear again, compare against the trash README before touching anything.

**Broken `related` links repaired in 112 notes.** Frontmatter held `  - - - Note Name` (a nested YAML list, not a link) — `[[Note]]` written unquoted and re-serialised. Rewritten to `  - "[[Note Name]]"`; all 116 targets resolve.

**Status vocabulary normalised:** `done` and `Completed` → `Done` (118 notes). Reading packs/notes typed `Course Reading`; the two Wikipedia readings typed `Research Source`.

**make.md views built.** Each University folder's `.space/` holds `context.mdb` (columns only — make.md fills rows from frontmatter at runtime) and `views.mdb` (`All` + `By Course`/`By Year`, grouped table). Built with `sqlite3` off the synced folder then copied in (SQLite can't lock files on the mount). Group column must stay visible or make.md silently skips grouping.

**Past items marked Done (2026-09-23, Oscar's request).** Every note dated before today that wasn't Done was set to `Done`: MSOA L01 and SM L01 lectures, 8 Revision notes (EA past papers 1–4, FoP Pandas revision/flashcards, FoP and I&E end-of-year exams), and the Year One/Two courses still marked In Progress (Business Economics, Global Challenges, Digital Skills). TaskNote `Rosthchild Assesment` set to `done` with `completedDate: 2026-09-22`.

**Views changed to one per course (2026-09-23, Oscar's correction).** Oscar wants a separate view per course, not one grouped view. Each type folder now has `All` plus one view per course that has notes in that folder (registry order: Year One → Three), in both the `.base` (full course names, filter `course == link("…")`, `Course` for Revision) and make.md (tabs use short codes so they fit: ACC, DS, EP, GB, GC, EA, PfS, BoE, BE, BRM1, G&T, BRM2, FoP, I&E, MSOA, SM, TEM). Courses has `Year One/Two/Three` (make.md: Y1/Y2/Y3). No grouped views remain.
How to apply: when a course gains its first note in a folder, add its view to that folder's `.base` and make.md `views.mdb`. make.md filters must be a flat list (`{"field","fn":"isLink","value":"<plain course name>","fType":"link","type":"link"}`) — nested filter groups are silently dropped, and `[[Name]]` values match nothing. Space `def.json` has `fullWidth: true` so the tabs fit; make.md's own `readableLineWidth` is forced back from Obsidian's setting, so don't bother editing it.

---

## 2026-09-23 — Admin folder reorganised

**Admin is split into `Claude/` (agent docs), `Templates/` (templates only), `Guides/` (Naming Conventions, TaskNotes Guide), `App/` (companion app spec + dashboard image) and `Archive/` (superseded files).**
Why: guides in `Templates/` cluttered the Templater picker; agent files had names (`Agents 2`, `Vault Index`) that didn't match the names every doc referred to.
How to apply: only templates go in `Templates/`. Agent files keep the names `AGENTS.md`, `CLAUDE.md`, `VAULT-INDEX.md`, `memory.md`, `open-items.md`. The redundant AGENTS pointer stub and an old BRAT log are in `Archive/`.


---

## 2026-09-23 — Tasks merged into their pages (Oscar's request)

**The page is now the task.** Oscar found separate TaskNotes files for things that already had a page redundant. 56 task files were merged into their pages and moved to `.trash/` (recoverable): 13 `Attend …` → the Lecture/Tutorial notes, 3 `Complete …` → the MSOA/SM Essay and Project notes, 40 `Apply to …` → Internship notes. Each page got `task` added to `tags`; internships also got the task's `priority`. TEM L01 (today) and the SM Team Project were tagged too. Task bodies were redundant (the pages already held the same session/deadline/Trackr detail).
- TaskNotes settings: field mapping `scheduled → date`; statuses replaced with the vault's `Not started` / `In Progress` / `Done`; default status `Not started`. `TaskNotes/Views/*.base` updated (`note.date`, `status != "Done"`).
- Internships: `deadline` renamed to `due` in all 163 notes, the template and `internships.base` (formula name `days_to_deadline` and view "Open deadlines" kept; column still displays "Deadline"). Needed because TaskNotes' `due` mapping is global. Template priority guidance changed to `low`/`normal`/`high`.
- Lecture/Tutorial/Essay/Projects templates now carry `task` in `tags`. Internship template does not — tag an internship when applying.
- 6 standalone tasks remain (no page of their own): BlackRock interview, TEM group survey (links the course hub), SM presentation-date confirmation (now a subtask of the SM Team Project page), dashboard, Edinburgh Award registration, Rothschild assessment (Done). Their `scheduled` became `date` and statuses were converted.
- Lost in the merge: the separate "scheduled ~2 weeks before" dates on coursework and "7 days before" on applications (pages only hold `due`), and the time-of-day on lecture schedules (in the Session details callout instead).
- Backup of everything touched: `.tasknotes-merge-backup-20260923/`.

---

## 2026-09-23 — Templates expanded; detail pulled from attachments (Oscar's request)

**Template bodies were expanded; frontmatter was not touched.** Lecture, Tutorial, Essay, Projects, Readings, Revision and Course templates gained detailed sections, and Internship and Unsorted gained one each. `Projects Template.md` previously had no body at all; it now has one built around the headings existing Project notes already use (Objective, Milestones, Tasks, Working notes). Reference Template (Zotero) unchanged. Backup: `.template-detail-backup-20260923/`.
Why: Oscar wanted more detail in notes, with detail pulled from attachments (slides, briefs, rubrics, PDFs), not just typed in.
How to apply: follow `AGENTS.md` §12 whenever a note is created or filled. Existing notes were **not** backfilled (Oscar's choice). Apply the new sections when a note is next worked on. Guidance text in the templates now uses the vault status words (`Done`, not `Completed`/`Submitted`/`Complete`).

---

## 2026-09-23 — Daily Claude/ folder sort set up (Oscar's request), first pass run

**A daily scheduled routine now clears `Claude/Inbox/` and `Claude/Unsorted/` automatically** (20:30 UTC / 21:30 BST), reading `AGENTS.md` + this file first each time, auto-filing everything using best-available context (course-name match first, then day-of-week/time-of-day against existing sessions when the label is generic), and logging inferences here rather than asking — per Oscar's instruction to be decisive, not blocked on confirmation.

**First pass (manual, this session) against `Claude/Inbox/Calendar Sync.md`:**
- Created 4 new MSOA lectures (L07–L10, 2026-10-12/15/19/22, all 09:00 · Business School LG.10 Lecture Theatre 4 — room inferred from every existing same-slot MSOA lecture) and MSOA's first two Tutorials (T01 "Computer Workshop" due 2026-10-16, T02 "Q&A Session" due 2026-10-23 — no room precedent for this slot, left blank). Added a "Management Science and Operations Analytics" view to `Tutorials/Tutorials.base` (its first Tutorial notes) — **`Tutorials/.space/views.mdb` (make.md) was not touched**, it's a SQLite file under the excluded `.space/` path (§1); add the equivalent view there by hand in the make.md navigator, or ask Claude to do it outside this routine if that changes.
- Created Strategic Management L04/L05 (2026-10-12/19) and T03/T04 "Seminar 3"/"Seminar 4" (2026-10-12/19). **Inference flagged**: from 2026-10-12 the calendar relabels the session "Lecture/01"/"Seminar/01" on Monday 15:10/16:10 instead of the usual Tuesday 14:10/16:10 "Lecture"/"Seminar/01" — treated as the same course continuing on a new slot (numbered next in sequence), not a parallel stream. No room precedent for the new Monday slot, left blank — worth confirming the room once known.
- Created Entrepreneurial Manager T02/T03 (due 2026-10-15/22), same slot/room as T01 (Business School LG.18 Lecture Theatre 2).
- Two amber "deadline" calendar items matched to the Strategic Management Team Project by content, not name: **"Team Groupwork Charter Submission box" (2026-10-13 14:00)** — inferred, no explicit brief mentions a charter yet, flagged for confirmation when the box appears on Learn — and **"Business Ideas - LEARN Submission Link" (2026-10-23 16:00)**, which lines up exactly with the project's own "Three business ideas — Friday of week 5" milestone, high confidence. Both filed as standalone TaskNotes (`projects: [[Strategic Management - Project - Team Project]]`), and added to the course note's 🗓️ Key dates and the project's Milestones line.
- `Claude/Inbox/Calendar Sync.md` itself was **not edited** — it's regenerated by the calendar-importer plugin, and past events already filed (2026-09-21 through 2026-10-08) were never marked off in it either. The routine's dedup works by checking whether a note/task for that course+date already exists before creating one, not by editing this file.
- `Claude/Unsorted/` was empty — nothing to fold in on this pass.

How to apply: on every future run, the two things worth double-checking against Oscar directly (not blocking, just flag if still unconfirmed) are the SM charter link and the SM Monday-slot room.

**Addendum, same day:** Oscar asked for the calendar sync checkboxes to be ticked once an event is filed. All 33 `- [ ]` boxes in `Claude/Inbox/Calendar Sync.md` were changed to `- [x]` (superseding the "leave it untouched" note above). Re-checking against the tick-box list caught one lecture missed on the first pass — **The Entrepreneurial Manager L05** (2026-10-21, same slot/room as L02–L04) — now created. Going forward: tick the box for an event in the same edit that creates its note/task, and treat an already-ticked box as another (faster) way to detect "already filed", alongside the date/course check.

---

## 2026-09-25 — Daily Claude/ folder sort, second pass

**Session note:** the vault folder wasn't connected to the agent session at start of this run (0 connected folders); folder access was requested and granted before proceeding, so the routine ran in full. Flagging in case this recurs — if the folder is ever not reconnected and access can't be granted unattended, a future run will need to notify Oscar and stop rather than skip silently.

**`Claude/Inbox/Calendar Sync.md`: all 34 unticked events processed, all 34 boxes ticked.** The file's shape has changed since last pass — the calendar-importer plugin now splits it into "My Calendar Events" (open) and "Completed Calendar Tasks" (already `[x]`, persisted by the plugin across regeneration rather than by this routine editing it directly). Of the 34 open items: 27 were course Lecture/Tutorial/Seminar/Workshop sessions dated 2026-09-21 through 2026-10-23, every one of which already matched an existing note (checked by course + date against `Lectures/`/`Tutorials/` frontmatter — all created in the 2026-09-23 first pass); 5 were non-course admin items that already had matching TaskNotes (TEM group-formation survey, both Edinburgh Award register options). The remaining 2 were genuinely new and got standalone TaskNotes:
- `Attend Business Management and Business and Law Welcome Back Session` (2026-09-30 11:00, LG.19 LT1B) — context `admin`, no course.
- `Register for Sustainable Futures Green Job Career Readiness Workshop` (2026-10-08 11:00, UEBS Conference Room 4th Floor) — context `careers`, no course.
No new Lecture/Tutorial notes were needed this pass — the first pass on 2026-09-23 already covered every course session through 2026-10-23.

**`Claude/Unsorted/` held a raw PDF, not a markdown Unsorted note** (`MSOA-Week 1-L2-2026_posted.pdf`) — doesn't match the Unsorted Notes Template's raw-notes-with-sections format, so handled by judgement rather than the template's own merge instructions. Its title slide ("Week 1(Lecture 2): An Introduction to MSOA") matched [[Management Science and Operations Analytics L02 - Lecture 2]] (date 2026-09-24) unambiguously. Filed to `Resources/Management Science and Operations Analytics/Slides/lecture-02-example-problems-overview-2026-09-24.pdf` and linked in the note's `resources`; full detail extracted per AGENTS.md §12 (learning objectives, lecture structure, four worked examples — Edinburgh Bakery simulation, DP shortest-path, CmpuTel EOQ with discount, RBS queuing — definitions, formulas, key concepts, exam-relevance). `status` set to `Done` (past lecture, matching the "past items marked Done" convention). Raw PDF deleted from `Unsorted/` afterward, per the template's own "don't let both versions sit around" instruction. Worth confirming with Oscar: is a raw slide PDF landing in `Unsorted/` (rather than `Inbox/`) expected/recurring, or a one-off from wherever synced it there?

How to apply: if a raw file (not a `.md` note) appears in `Unsorted/` again, match it to a Lecture by content the same way, file it under `Resources/{Course}/Slides/` (or the appropriate type folder) with the vault's lowercase-hyphenated naming, extract per §12, and delete the original once folded in.

---

## 2026-09-25 — Lecture Template: Notes section rewritten to Oscar's own note style (Oscar's request)

**Only the 📝 Notes section of `Admin/Templates/Lecture Template.md` changed** (plus one guidance line under "How to organise"). Frontmatter and all other sections untouched. Backup: `.template-notes-backup-20260925/` (template, AGENTS.md, memory.md as they were).
Why: Oscar liked the expanded templates but the Notes section lacked detail versus his hand-written notes. He wants it "exactly like" his format: plain headings such as `What is Ethnography?`, `The Ethnographic Approach`, `When to Use Ethnography`, `Roles of the Ethnographer`, `Gaining & Maintaining Access`, `Challenges of Ethnography`, then plain `* ` bullets, each a dense fact with (Author, Year) citations, `Note:` bullets, `—` separators, and indented numbered sub-lists (e.g. "Three approaches (Bell, Bryman & Harley, 2019): 1. 2. 3."). No callout box, one heading per lecture section, whole lecture covered.
How to apply: follow `AGENTS.md` §12 point 9 when creating or filling any Lecture note. Existing lecture notes were **not** rewritten (only the template changed). Other templates (Tutorial, Reading, Revision, etc.) not changed. Offered to Oscar: re-format existing lecture Notes sections to this style, starting with BRM2 L10.

**Addendum, same day — existing lecture Notes restyled (Oscar's request):** Lecture Notes sections restyled to the new plain style in **111 of 181** lecture notes (### / #### headings → plain heading lines with a blank line after, `- ` → `* `, bold/italic markers and stray `---` rules and empty `<!-- Column -->` comments removed, tabs → 3 spaces). Every word kept; all text outside the Notes section verified byte-identical to backup `.lecture-notes-backup-20260925/`. **Deliberately skipped, left as they were (70):** notes whose Notes section holds tables, callouts, images, LaTeX maths, code blocks or HTML, because flattening those would break them — Accountancy 1A (8), Business Economics (6), Business Research Methods 2 (1), Business Research Methods One (4), Economic Applications (4), Economic Principles (7), Fundamentals of Programming (2), Globalisation and Trade (6), Innovation and Enterprise (2), Management Science and Operations Analytics (10), Planning for a Startup (6), Strategic Management (5), The Business of Edinburgh (4), The Entrepreneurial Manager (5). **Also ignored, per Oscar:** 18 lectures with empty Notes (MSOA, Entrepreneurial Manager, Strategic Management) — lectures haven't happened yet; fill in the new style when they do. No slide detail was added to existing notes; only formatting changed.

**Correction, same day (Oscar):** the Notes section must sit **inside a `> [!note]+ Lecture notes` callout like the other sections** (my first template rewrite removed the callout). The plain headings / `* ` bullets style now lives inside the callout. Template, AGENTS.md §12 point 9 and all lecture notes with content (164) were re-wrapped; backup of the pre-wrap state: `.lecture-notes-backup-20260925b/`. The 18 empty (not yet delivered) lectures still carry the template's original empty callout/comments.
**Also same day:** Oscar asked to add as much slide detail as possible to existing lecture Notes. Done so far by reading each deck against the note and appending new plain-style sections inside the callout (never editing his lines): BRM2 L03, L05, L10; G&T L03, L13, L15, L16; SM L01; MSOA L01, L02; I&E L13; EA L08, L18; BoE L07. Note: `Globalisation and Trade L03` Notes hold statistics content unrelated to its New Trade Theories deck (likely a Notion mix-up) — left in place, slide-based sections appended. Templates were also moved into `Admin/Templates/Claude/` (+ `Human/`) by someone else during this session.


- 2026-09-25 (Claude): Slide-detail enrichment pass (Notes inside `> [!note]+ Lecture notes` callout, "Extra Detail from the Slides" sections appended, nothing removed). Enriched: BRM2 L03/L05/L06/L10; G&T L03/L13/L15/L16; SM L01; MSOA L01/L02; I&E L13; EA L03/L08/L09/L10/L13/L16/L18/L19; BoE L07; P4SU L09; BRM One L03; Global Business L02; Business Economics L02. Integrity check passed (all 181 lectures keep every original line). Not yet enriched: ~50 lectures with smaller gaps (e.g. BRM One L10/L11/L13/L15/L19, I&E L05, P4SU L04/L06-08, G&T L06/L09/L10/L14, BoE L08-16, Accountancy 1A .ppt files); BRM One L02 textbook skipped deliberately; image-only slides can't be extracted. G&T L03 original notes contain unrelated statistics content (likely Notion mix-up).


---

## 2026-09-25 — Admin folder made the single reliable source of truth (Oscar's request)

**Oscar asked for the Admin folder to be fully organised so Claude always does things the right way.** Audit first (live vault vs. every Admin doc), then rewrite. Backup: `.admin-backup-20260925/` (Admin as it was at 08:5x).
Findings: the notes themselves were clean — 628 notes, 0 frontmatter deviations against the templates, every `base` and `course` link resolving. The docs had drifted: AGENTS.md said 429 notes / seven folders / no Internships or TaskNotes / templates at `Admin/Templates/`; the course registry carried stale statuses; §1 listed 3 of the ~12 dot-directories to skip; open-items counted problems that were already fixed (`type: Reading`) and missed new ones; `Admin/App` and `Admin/Archive` are recorded above as existing but are gone.
What changed:
- **`AGENTS.md` rewritten.** New §0 "Session protocol" makes the project instructions binding: read admin first (INDEX → AGENTS → open-items → newest memory), plan + task list before acting, back up before bulk edits, work in place and re-read after writing, verify with `verify-vault.py`, log here. Added: Internship schema, all 8 note folders, TaskNotes, the root `Claude/` intake tray, template locations (`Templates/Claude`, `Templates/Human`), "skip every root dot-directory", naming for Internships/tasks, filing rules (individual report → Essays, group → Projects, seminars → Tutorials), sync hazards. Course registry now lists year/semester only (status lives in the hub notes). Counts removed from AGENTS.md — the index and the script own them.
- **`verify-vault.py` added** (`Admin/Claude/`, read-only). Checks frontmatter key order vs template, `base`, course names, status/type vocabularies, naming patterns, flat folders, duplicate titles, link resolution, admin files present. Result on 2026-09-25: 0 FAIL, 56 WARN (all known open items).
- **`VAULT-INDEX.md`, `open-items.md`, `CLAUDE.md`** refreshed. `open-items.md` now also carries the unfinished template-backfill and lecture-enrichment work, the missing `Admin/App`/`Admin/Archive`, the missing make.md MSOA Tutorials view, one broken link (I&E L11), and the no-root-CLAUDE.md gap.
How to apply: start every session with `AGENTS.md` §0. Re-run `verify-vault.py` after any structural change and before finishing. Keep counts out of AGENTS.md. If a doc and the vault disagree, the vault + `verify-vault.py` win — fix the doc.


---

## 2026-09-25 — `Claude/Inbox/Learn.md` created (Oscar's request)

**New file `Claude/Inbox/Learn.md`, modelled on `Calendar Sync.md`** (open items, completed items, error reporting), plus a to-do checklist for the three Year Three courses. Oscar chose: contents = assessments and deadlines, weekly content and readings, announcements, grades and feedback; to-do as a checklist inside Learn.md (no TaskNotes created); whole semester; Learn items only (no extra study-prep tasks).
Source: read-only pass through Oscar's logged-in Learn session (built-in browser) — nothing on Learn was changed. Read: front pages, announcements, gradebooks, Assessment and Feedback Information, MSOA case-study submission details, SM Course Plan image. The folders not opened are listed under Error Reporting in the file. Unlike Calendar Sync, this file is **not** regenerated by a plugin — it is a snapshot; refresh it by re-reading Learn.
How to apply: the daily `Claude/` sort should treat Learn.md like Calendar Sync — file each unticked item as a note/task only if none exists for that course + date (dedup by course + date), tick the box in the same edit, and do not delete the file. Nothing was filed into notes or TaskNotes in this session.
**Discrepancies found against the vault, all left unchanged and listed in Learn.md for Oscar:** (1) the Groupwork Charter (Tue 2026-10-13 14:00) belongs to The Entrepreneurial Manager on Learn, but the vault task `Submit Strategic Management Team Groupwork Charter` ties it to the SM Team Project — this corrects the 2026-09-23 inference above; (2) the TEM group formation survey closes 2026-09-30 14:00, the vault task says 2026-10-09 10:00; (3) SM Group Presentation is Tue 2026-12-01 14:00 (30%) and the Team Project `due` is still empty (closes the "presentation date TBC" open item once Oscar confirms); (4) TEM has no Project/Essay notes for its draft document (2026-11-10), Group Presentation (2026-11-24, 40%) or Individual reflective report (2026-12-08, 60%). Other dates found: MSOA Group Case Study 2026-10-29 and Individual Case Study 2026-12-03 already match the vault; MSOA exam date TBC (Central Exams); SM Business Ideas 2026-10-23 is 0% (unmarked); SM Individual Report 2026-12-18 (70%) matches.


---

## 2026-09-25 — Weekly Summary template drafted for review (Oscar's request)

**New file `Admin/Templates/Claude/Weekly Summary Template.md`**, in the same style as the other templates (info callout, emoji `##` headings each with a callout, "How to organise" guidance). Frontmatter: `tags, base, Week No., date, status, related, summary` (no `course`, since a week spans courses; `date` = Monday; `base` left empty like the other templates). Sections: Week details, Focus, Courses this week, What I learned (plain Lecture-notes style), Completed, Carried over, Next week, Deadlines, Careers & internships, Questions, Reflection, Source notes, End of week.
**Draft only — deliberately not wired in.** No folder, `.base`, make.md view, naming rule or verify-vault.py entry was added, and no notes created. Proposed title: `Weekly Summary - Year {N} S{N} Week {NN}`. If Oscar approves: add folder + `.base` + FOLDERS entry in verify-vault.py + AGENTS.md §2/§4/§5 + VAULT-INDEX, then backfill. `verify-vault.py` after adding: 0 FAIL, 56 WARN (unchanged).

**Addendum, same day (Oscar's request):** Weekly Summary template now has a per-item section for each note type, each with a repeatable `### [[note]]` block inside a callout: 🎓 Lectures, 🧑‍🏫 Tutorials, 📄 Readings, ✍️ Essays & projects, 🔁 Revision (Internships stay in 💼 Careers & internships). "What I learned" is now the cross-week synthesis only. Still a draft; not wired into folders, `.base` or `verify-vault.py`. Checker after edit: 0 FAIL, 56 WARN.

## 2026-09-25 — TaskNotes times restored on upcoming sessions

**Problem (Oscar):** TaskNotes wasn't applying times. Cause: the 2026-09-23 "page is the task" merge dropped time-of-day from lecture/tutorial scheduling (see the 2026-09-23 "Lost in the merge" line), so `date` (lectures) and `due` (tutorials) were date-only and the calendar showed them all-day.

**Fix:** for every not-Done lecture/tutorial dated 2026-09-25 or later (16 lectures, 9 tutorials/seminars — MSOA, Strategic Management, The Entrepreneurial Manager), the time is now in the frontmatter value (`date: 2026-09-28T09:00`; tutorials `due: 2026-10-16T14:10`) and the Session details `Date & time` line. Times come from the weekly timetable in `Calendar Sync.md`: MSOA lectures 09:00, MSOA workshop/Q&A Fri 14:10, TEM lecture Wed 09:00, TEM tutorial Thu 13:10, SM Tue 14:10 lecture + 16:10 seminar until 2026-10-05, then Mon 15:10 lecture + 16:10 seminar from 2026-10-12. Also `Register for Edinburgh Award…` due set to 2026-09-30T13:30 (Option 1 start).

**How to apply:** new lectures/tutorials should carry the time in `date`/`due` (`YYYY-MM-DDTHH:MM`) — TaskNotes and the .base views accept it. No field added, so the template still matches. Done/past notes were left date-only (times not recorded). Essays/Projects/Internships `due` have no known times, left date-only. Backup: `.tasknotes-times-backup-20260925/`.

## 2026-09-25 — Times backdated (only where recorded)

Oscar asked to backdate the TaskNotes times. Only past sessions with a time actually on record were changed (11 lectures): Accountancy 1A L01/L03/L05/L08/L10/L12 (Mondays 16:10), L02/L07 (Fridays 09:00, online — from the L01 note's "Mondays 16:10–18:00 on campus; Fridays 09:00–09:50 online"), MSOA L01/L02 (09:00), Strategic Management L01 (14:10). Accountancy L04/L06/L09/L11/L13 fall on other days/clashes and were left date-only.
Every other past lecture and all past tutorials have no time in the vault, Notion export or backups (the Notion Revision `date` times are creation stamps, not sessions), so none was invented. How to apply: add `THH:MM` to `date`/`due` only when a timetable source exists; ask Oscar for the timetable of a course before filling it. Backup: `.tasknotes-times-backup-20260925/`.

## 2026-09-25 — Times backdated from Oscar's timetable feed (Sem 1 2025)

Oscar supplied his university timetable .ics (48 events, 2025-09-26 → 2025-11-18: Business Economics, Globalisation and Trade, Business Research Methods One). 44 lectures/tutorials matched exactly by course + type + date and got `THH:MM` in `date`/`due` and the Session details `Date & time` line (start time only; the feed's end times and rooms were not copied). Weekly pattern: BE lecture Mon 10:00, BE tutorial slot Mon/Wed 12:10–14:10; GT lecture Tue 12:10 + Fri 09:00, GT seminar Fri 11:10; BRM lecture Tue 13:10 + Wed 12:10, BRM tutorial Tue 14:10.
Not applied (no feed event on that date, so no time invented): BE L01–L02, BRM L01–L05/L08/L20, GT L01–L02/L04/L15–L16, BE T04–T08, BRM T07. The feed only covers those three courses, Sep–Nov 2025; the Semester 2 and Year 1 sessions still have no source. Backup: `.tasknotes-times-backup-20260925/`.


---

## 2026-09-25 — Strategic Management readings added from the Course Plan screenshot (Oscar's request)

**Added 3 Reading notes** (`Course Reading`, `Not started`, linked to the SM lecture for the set week): Porter (1996) What Is Strategy (Week 1, L01); Bazerman (2020) A New Model for Ethical Leadership (Week 4, L04); Baker and Nelson (2005) Creating Something from Nothing… Bricolage (Week 5, L05). Titles, journals and URLs verified by web search, not from PDFs; no PDFs are filed yet, so summary, Structure and notes are left empty (AGENTS §12: never invent). `?` and `:` dropped from filenames per Naming Conventions.
**Not added — title could not be verified:** Smith et al. (2016), King et al. (2021), Fanton and Silva (2023), Hooker (2010), Wade and Wirtz (2026), Nesterova (2020); Reath (2013), Elkington (2018), Cui et al. (2023) are only in Learn.md, not the screenshot. Case studies (Richard Henkel GmbH, Apple) and the Whittington chapters were not added (Whittington already has a note). How to apply: get exact titles from the Learn reading modules or PDFs, then add with the same pattern; lecture `readings` fields were left untouched.

**Addendum (same day, Oscar asked to search titles):** added Nesterova (2020) - Degrowth Business Framework (Week 7). Matched by author, year and the sustainability topic; the Course Plan title is cut off, so Oscar should confirm on Learn. Web search found no verifiable title for Smith et al. (2016), King et al. (2021), Fanton and Silva (2023), Hooker or Wade and Wirtz (2026); not added. Hooker's search returned only unrelated candidates.

## 2026-09-25 — `due` field added to Readings; SM readings are now tasks (Oscar's request)

Schema change: Readings template now `tags` (with `task`), … `date, due, authors…`; `Readings.base` gained a Due column in every view; all 132 Readings backfilled with an empty `due:`. The four new Strategic Management readings carry `task` and a `due` = the lecture they are set for (Porter 2026-09-22T14:10, Bazerman 2026-10-12T15:10, Baker and Nelson 2026-10-19T15:10, Nesterova 2026-11-02T15:10 — Nesterova's time assumes the Monday 15:10 lecture pattern, since no L07 note exists yet). Existing readings were NOT tagged `task`. AGENTS §4 and TaskNotes Guide updated. Not done: make.md `Readings/.space/views.mdb` has no Due column (edit only with Obsidian closed). Backup: `.reading-due-backup-20260925/`.

**Update (same day):** Oscar asked for the day before the lecture instead. SM reading `due` values are now date-only: Porter 2026-09-21, Bazerman 2026-10-11, Baker and Nelson 2026-10-18, Nesterova 2026-11-01 (replaces the lecture-time values above). Applied to the four SM readings only; other readings are Done/course-less and untagged.

**Update (same day):** Oscar meant every reading he gave, so five untitled ones were added as placeholders named `{Author} ({Year}) - Title To Confirm` (Smith et al. 2016, King et al. 2021, Fanton and Silva 2023, Hooker 2010, Wade and Wirtz 2026), `task`-tagged with `due` = day before the lecture. Full citation/url/item type left blank (never invent). How to apply: when the real title is known, rename the note (update any links), fill the citation fields, and drop the placeholder wording. Henkel and Apple case studies and the Whittington chapters were not added (no author/year to name them).

**Fix (same day):** SM readings did not appear in TaskNotes. TaskNotes maps its scheduled field to `date`, and these notes held the publication year (`date: "2020"`), not a valid date. For the nine task-tagged SM readings `date` is now the same day as `due` (the day before the lecture), so the year is kept only in the citation fields. Plugin config checked (tag `task`, Readings folder not excluded). How to apply: any Reading that becomes a task needs a real `date`. Backup: `.reading-due-backup-20260925/after-first-pass/`.

**Update (same day):** Oscar said not everything he uploaded was added, so the rest of the Course Plan was added, all `task`-tagged with `date`=`due`=day before the lecture: 6 Whittington chapter notes as Book Sections (Macro-Environment Analysis, Industry and Sector Analysis, Resources and Capabilities Analysis [Week 2, 2026-09-28]; Business Strategy and Models, Corporate Strategy [Week 3, 2026-10-05]; International Strategy [Week 8, 2026-11-08]) with chapter pages from the PDF's contents page and the set pages from the plan/Learn.md; Elkington (2018) (verified HBR title); Reath (2013) and Cui et al. (2023) as `Title To Confirm` placeholders (not in the screenshot, from Learn.md); and the Henkel and Apple cases as `Case Study - {Title}` because no author/year is on the plan (author/year to fill in). Total task-tagged SM readings: 20. The main Whittington note was left as is.

## 2026-09-25 — SM Week 2 readings filled from the Whittington PDF; study document (Oscar's request)

Oscar asked for the week's reading as the actual text. Claude does not reproduce book text, and AGENTS §12 says summarise rather than paste, so the three Week 2 Whittington notes (Macro-Environment Analysis pp. 36–49, Industry and Sector Analysis pp. 64–74, Resources and Capabilities Analysis pp. 94–117) were filled with own-words summaries read from the set pages of the PDF. Filled: `summary` (frontmatter), Edition, Structure, Summary, Key points (page-cited), Key argument, Definitions & frameworks, Connections, Use in writing. Left untouched on purpose: My commentary, My take, Notable quotes (no verbatim text), Method & evidence (textbook), DOI/ISBN (not verified). Printed page = PDF page − 27 for these chapters. Use-in-writing links are marked "candidate source; confirm against the brief". The same content is in `Claude/Claude outputs/week-2-reading-notes.md` (one file). Earlier `next-week-reading-list.md` (a to-do list, not what Oscar wanted) left in place. Note: `Claude outputs/` now sits under `Claude/`, not at the vault root. Backup: `.week2-readings-backup-20260925/`.

**Update (same day):** Oscar asked for `Claude/Claude outputs/week-2-reading-notes.md` to run about 20 minutes read aloud. It was rewritten as a prose, spoken-style script of about 3,200 words (about 150 words a minute), no tables. The longer table version is kept in `.week2-readings-backup-20260925/week-2-reading-notes-long.md`. The three Readings notes are unchanged by this.

**Correction (same day):** Oscar did not want the doc cut. `Claude/Claude outputs/week-2-reading-notes.md` is restored to the full version (about 4,200 words, with tables). The 20-minute spoken script (about 3,200 words) is kept as a separate file, `Claude/Claude outputs/week-2-reading-script-20min.md`.

**Update (same day):** Oscar will upload the Week 2 reading to ElevenReader (text to speech). Created `Claude/Ellevenread/` with `week-2-reading-elevenreader.md`: all the content of the full version (about 4,200 words, about 28 minutes read aloud), rewritten with no tables or markdown symbols, page ranges spelled out ("pages 36 to 49"), abbreviations expanded. The full table version stays in `Claude/Claude outputs/week-2-reading-notes.md`.

**Update (same day):** Oscar wanted the ElevenReader version to sound like a podcast, titled from the book and chapters. Added `Claude/Ellevenread/exploring-strategy-chapters-2-to-4-podcast.md`: a solo-host conversational script (about 7,500 words) covering all the content of the full version, titled "Exploring Strategy, Chapters 2 to 4: Reading the Environment, the Industry and the Organisation". The earlier plain version `week-2-reading-elevenreader.md` is kept alongside it.

## 2026-09-25 — Where Claude deliverables go (Oscar's instruction)

Deliverables that are not notes (study docs, scripts, exports) go in the existing `Claude/Claude outputs/` folder. Do not create new folders for them, and do not create a `Claude outputs/` at the vault root. Checked 2026-09-25: only `Claude/Claude outputs/` exists. The one exception is `Claude/Ellevenread/`, which Oscar asked for by name for text-to-speech files.

## 2026-09-28 — Daily Claude/ folder sort, third pass

**`Claude/Inbox/Calendar Sync.md`: nothing to do.** "My Calendar Events" (the open section) was empty — every event already sits in "Completed Calendar Tasks", all ticked. No new notes/tasks needed.

**`Claude/Unsorted/` held 2 raw PDFs + 1 raw notes.md, all already folded in by the time this pass ran** (`Notes from morning lecture today.md`, `MSOA-Week 2_L1_2026_posted.pdf`, `Case Study for morning lecture.pdf`, all dated/modified this morning). [[Management Science and Operations Analytics L03 - Lecture 3]] — the National Cranberry Cooperative case, RP1 overtime/truck-queuing — was already created and fully filled (checked against the raw notes: every point in them, e.g. "6.4 hours of overtime", "58% wet", dumping-bay/bin queuing, is covered in the note's Notes/Definitions/Frameworks sections), and both PDFs were already copied into `Resources/Management Science and Operations Analytics/` (`Slides/lecture-03-national-cranberry-cooperative-2026-09-28.pdf`, `Documents/national-cranberry-cooperative-1996-case-study.pdf` — md5-verified byte-identical to the Unsorted originals) and linked in the note's `resources`. Course note's 🗓️ Key dates already had Coursework 1 (the case study report this lecture builds toward). So this pass's only actual work was cleanup the earlier fill-in missed: moved the 3 raw Unsorted files to `.trash/Unsorted-cleared-20260928/` (not `rm`, per the vault's never-delete-on-Oscar's-behalf rule) so the raw captures and the finished note don't both sit around, per the Unsorted template's own instruction. `verify-vault.py`: 0 FAIL, 56 WARN (unchanged).

How to apply: when Unsorted/Inbox content shows as already actioned in the note graph (resources filed, note fully written) but the raw files are still sitting in `Claude/Unsorted/`, treat the fold-in as done and just clear the tray (move to `.trash/`) rather than re-doing the work — verify coverage first by diffing the raw notes against the target note's content, don't just trust an "After the lecture" checklist that says `[x]` (this one did, before the files were actually cleared).


## 2026-09-29 — Daily Claude/ folder sort, fourth pass

**`Claude/Inbox/Calendar Sync.md`: 3 of 3 open events processed, all boxes ticked.** Two ("Deadline of Take survey — TEM Group Formation", "TEM Group Formation", both 📅 2026-10-06) matched the existing standalone task `TaskNotes/Tasks/Complete Entrepreneurial Manager Group Formation Survey.md` and the course note's Key dates — not re-created, just ticked. This is the *third* date seen for this same survey deadline (Learn said 2026-09-30 on 2026-09-25; the task itself says 2026-10-09; now Calendar Sync says 2026-10-06) — left all three in the course note's Key dates rather than picking one, flagged in `open-items.md` for Oscar to check on Learn directly. The third ("Group Case Study — Submission Link", 📅 2026-10-29, Thursday 14:00) matched the existing `Projects/Management Science and Operations Analytics - Project - Group Case Study.md` (due 2026-10-29) exactly — ticked, no new note.

**`Claude/Unsorted/` held one raw slide PDF and one non-vault file.** `Week 1 - The Entrepreneurial Manager 2026-27 - Student copy.pdf` (45 slides: course briefing + the Week 1 "Opportunities" lecture) matched [[The Entrepreneurial Manager L01 - Lecture 1]] unambiguously (title slide + date). Filed to `Resources/The Entrepreneurial Manager/Slides/lecture-01-introduction-opportunities-2026-09-23.pdf` (md5-verified byte-identical, new `Resources/The Entrepreneurial Manager/` folder created — closes part of open-items #9) and linked in the note's `resources`; full detail extracted per AGENTS.md §12 (learning objectives, lecture structure, Pick Protection and Lupo/Xupo examples, opportunity identification/exploitation factors, definitions, key concepts) into the Notes callout in the plain style. `status` set `Done`. Since this deck also serves as the course's de facto handbook (org contact details, delivery schedule, assessment structure, full 11-week topic list), also filled the course note's Course details, Learning outcomes, Assessment, Key dates, Weekly schedule (Weeks 1–5, matched against existing L01–L05/T01–T03 dates) and Syllabus sections, all cited to slide numbers — this went beyond the lecture note itself but the source directly supports it (AGENTS §12 table: "Course handbook / L01 slides" → course note sections). Raw PDF moved to `.trash/Unsorted-cleared-20260929/` after folding in.

**`Claude/Unsorted/creds.txt` was NOT processed as vault content — flagged instead.** It's a pasted RTF fragment (not a `.md` note, doesn't match the Unsorted template) containing what reads as a live access-key ID/secret key pair. Left in place untouched (no deletion or filing without Oscar's say-so); logged as a new open item (`open-items.md` §11) and reported directly to Oscar as a possible credential leak, since it's sitting in a OneDrive-synced folder.

**Found at session start: every `.{thing}-backup-*` folder and `.trash/` were missing from the vault root** — not caused by this session (nothing was deleted), most likely the same OneDrive sync loss already seen for `Admin/App`/`Admin/Archive` (open-items #8). Logged as open-items #12. `.trash/` was recreated this session to hold the cleared Unsorted PDF.

`verify-vault.py`: 0 FAIL, 56 WARN (unchanged — Readings count now shows 149 in the checker output vs. 128 in `VAULT-INDEX.md`, which is stale from other work outside this routine and wasn't refreshed here).


## 2026-09-29 — Fix: unquoted colon broke frontmatter YAML on TEM L01

Oscar reported Obsidian showing "invalid properties" on `Lectures/The Entrepreneurial Manager L01 - Lecture 1.md` (screenshot: frontmatter rendering as raw source text instead of the Properties panel). Cause: the `summary` value written in the fourth-pass fold-in above contained an unquoted `: ` mid-string ("...first lecture topic: entrepreneurial opportunities...") — YAML reads a bare `key: value` colon-space anywhere in an unquoted scalar as a new mapping key, which breaks the whole frontmatter block. Confirmed with `yaml.safe_load` (not just eyeballing) and scanned every note's frontmatter the same way — this was the only file in the vault with invalid frontmatter YAML, isolated to today's edit.

**Fix:** wrapped the `summary` value in double quotes (content unchanged). Re-parsed clean; `verify-vault.py` still 0 FAIL, 56 WARN.

**How to apply going forward:** any `summary`/free-text frontmatter value containing a colon followed by a space must be double-quoted, not left as a bare scalar — `verify-vault.py` does not currently catch this (it didn't flag the broken file as FAIL or WARN), so this class of error is invisible to the checker and only shows up as Obsidian's "invalid properties" warning. Worth considering adding a real YAML-parse check (`yaml.safe_load` per note, not just field-presence checks) to `verify-vault.py`.


## 2026-09-29 — Vault moved from OneDrive to iCloud Drive

Oscar moved the whole vault to `~/Library/Mobile Documents/com~apple~CloudDocs/Second Brain`. Checked after the move: 1,375 files (688 .md, 1.3 GB), no `.icloud` placeholders, no absolute OneDrive paths in any note (all file links are vault-relative, e.g. `OneDrive/{Course}/...`, so nothing broke), Obsidian has the new path registered and open. `verify-vault.py`: 0 FAIL, 56 WARN (unchanged). The old OneDrive `Second Brain` folder is empty (0 files) and the old vault entry is still listed in Obsidian's vault switcher; both left alone.

**Changed:** AGENTS.md sync-hazards line now says iCloud; the daily "Claude folder sort" scheduled task prompt was repointed from the OneDrive path to the iCloud path. **Deliberately not changed:** the `OneDrive/` file-store folder keeps its name (renaming would break every `onedrive` link and the templates); older memory.md / open-items.md entries mentioning OneDrive are history and stay as written. The empty `.tmp.drivedownload/` and `.tmp.driveupload/` folders at the vault root are OneDrive leftovers, harmless, left in place.

## 2026-09-29 — Daily Claude/ folder sort, fifth pass (Unsorted only)

**`Claude/Inbox/Calendar Sync.md`: nothing to do.** "My Calendar Events" was empty; everything already sits ticked under "Completed Calendar Tasks" (the fourth pass, logged above, covered it).

**`Claude/Unsorted/` held 4 items to fold in, plus `creds.txt` (unchanged — see the 2026-09-29 security flag above, still not resolved).** All 4 matched cleanly to today's Strategic Management Week 2 session (lecture 2026-09-29 14:10, seminar/"Seminar 1" 16:10):
- `2 Week_Lecture StM_in class.pdf` (54 slides) → filed to `Resources/Strategic Management/Slides/lecture-02-strategic-analysis-2026-09-29.pdf` (md5-verified byte-identical) and linked in [[Strategic Management L02 - Lecture 2]]'s `resources`; full detail extracted per AGENTS.md §12 into the Notes callout in the plain style (strategy-development process, why/how of strategic analysis, then the BMW EV case worked through all 8 process steps — Five Forces, PESTEL, value chain, VRIO, stakeholder/ethics, SW, relational SWOT — plus the Heineken SWOT example), Definitions, Frameworks (with each framework's limitation noted), Key concepts. `readings` linked to the three Whittington Week 2 chapter notes (Macro-Environment, Industry and Sector, Resources and Capabilities Analysis) — matches the course plan table from L01. `status` set to `Done`.
- `2 Week_Seminar StM.pdf` (5-page exercise sheet, ungraded) → filed to `Resources/Strategic Management/Documents/seminar-01-strategic-analysis-exercise-adidas-2026-09-29.pdf` (md5-verified) and linked in [[Strategic Management T01 - Seminar 1]]'s `resources`; the three tasks (Five Forces / PESTEL / Value Chain & VRIO on Adidas) copied verbatim into "The task" per §12. `status` set to `Done`.
- `Adidas PESTEL - Strategic Management Week 2 Seminar Task 2.md` — not an Unsorted-template note; a raw capture from Oscar's own separate Claude session (self-labelled, with links to a Claude Docs write-up and a slide deck) containing the completed Task 2 (PESTEL) analysis for the seminar. Matched to T01 (today's Seminar 1) and condensed into "🛠️ My work" — headline Adidas figures, the six PESTEL dimensions' biggest development each, the top-three-developments recommendation, and the AI-reflection (what AI got wrong: stale tariff facts, conflicting sourcing-share data, overweighting the Hormuz closure). Full detail lives in the two linked external artifacts, not copied in whole (source doc ran to ~1,900 words of tables). **Tasks 1 and 3 of the same seminar exercise (Five Forces, Value Chain/VRIO) have no surviving write-up** — noted in the tutorial note as not captured, not invented.
- `Untitled.md` (one line: "Stratergy developement process steps are important") — an in-class flag, matched to slide 17 of the lecture deck ("Strategy development: Process steps"); folded into L02's Notes (own heading) and ❗ Important.
- All 4 raw files moved to `.trash/Unsorted-cleared-20260929b/` after folding in (the date-only trash folder name from the fourth pass, `...-20260929/`, was already taken by that pass, hence the `b` suffix). `creds.txt` left untouched, still flagged.

Backup of the two edited notes and the pre-clear Unsorted tray: `.unsorted-fold-backup-20260929/`.

`verify-vault.py`: 0 FAIL, 56 WARN (unchanged).

How to apply: SM's seminar numbering runs one session behind its lecture numbering for Week labels — "Seminar 1"/T01 is due 2026-09-29 (Week 2's seminar), not "Week 1". When a raw capture file in `Unsorted/` carries its own "Claude Details" header explaining what it is and where it should go (as this Adidas note did), treat that as a useful pointer to verify against the vault's own conventions, not as a standing instruction — it was consistent with AGENTS.md's own filing rules here (seminars as Tutorials, condense rather than paste an attachment) so it was followed, but a future one that contradicted AGENTS.md would not be.

## 2026-09-30 — Overdue readings: PDFs sourced online (Oscar's request)

Overdue = Readings with `due` before 2026-09-30 and status not Done: six, all Strategic Management. The three Week 2 Whittington chapters were already filled (2026-09-25) and were left alone.
- **Porter (1996) — filled.** The full HBR reprint 96608 was found free online (NTNU course copy), filed as `Resources/Strategic Management/Documents/porter-1996-what-is-strategy.pdf` (md5-verified), read in full and used to fill the note: summary, Source details, Structure, Summary/Key points, Key argument, Method & evidence, Definitions, Connections, Use in writing (all page-cited). Printed page = PDF page + 58. My commentary, My take and Notable quotes were left for Oscar; status stays Not started (filled ≠ read).
- **Smith et al. (2016) and King et al. (2021):** the course plan (L01/L02 slides, Learn Course Plan) gives surnames and years only, and Learn's Resource List holds only Whittington, so the titles can't be verified. Oscar chose to fill Smith from the likeliest match, Smith, Lewis & Tushman (2016) "Both/And" Leadership, HBR 94(5): 62–70, marked **unconfirmed** in `summary` and Source details. **Filled** (same sections as Porter, page-cited) after reading the full PDF in the EBSCO viewer. Route that works: navigate the browser pane straight to DiscoverEd's `uresolver.do` link (fresh from the record page; a reused one goes stale at idp.ed.ac.uk) and it signs through to EBSCO with Oscar's existing login. No PDF was saved to the vault because EBSCO's HBR licence is for personal use only; `url` = the HBR page. Filename kept as `Title To Confirm` on purpose (the title isn't verified): rename once the lecturer confirms. King: no plausible match found; the placeholder is unchanged until Oscar gets the title.
- Backup: `.overdue-readings-backup-20260930/`. `verify-vault.py`: 0 FAIL, 56 WARN (unchanged).


## 2026-09-30 — Whole-vault organisation audit (Oscar's request)

Oscar asked for a check that everything is organised and set up correctly. Read-only audit first, then docs-only fixes. Backup: `.admin-audit-backup-20260930/`.
**Notes: clean.** `verify-vault.py` 0 FAIL, 56 WARN (all known open items). Extra checks beyond the script: every note's frontmatter parses as YAML (0 errors, so the 2026-09-29 colon bug hasn't recurred), no unquoted wikilinks in YAML, no nested folders or non-note files in the 8 note folders, no empty notes, every course with notes in a folder has its `.base` view, no `.icloud` placeholders. make.md views match the courses present except MSOA in Tutorials (known) and MSOA in Readings (new, one MSOA reading).
**Docs brought up to date:** VAULT-INDEX counts (649 notes, Readings 149), Resources has 16 course folders (TEM added 2026-09-29), `Claude/` row lists Learn.md, Claude outputs, Ellevenread, the Weekly Summary draft template noted; AGENTS "last verified" line and §2 (no `TaskNotes/Archive/` exists); open-items #7 (Readings make.md MSOA view), #9, #10, #11 (creds.txt still present, now in iCloud), #12 update, new #13 (small leftovers: kanban `.bak`, Sync Folders Pro marker, Icon files, misspelt `Rosthchild Assesment` task, `Upload Lecture Slides` task probably done).
**Deliberately not touched:** `Claude/Unsorted/` (new TEM Week 2 PDF and an empty `This mornings Lecture.md` — left for the 20:30 routine), `creds.txt`, Oscar's task titles/statuses, make.md databases (need Obsidian closed), TaskNotes/Views, every open item.
How to apply: consider adding a YAML-parse check to `verify-vault.py` (suggested 2026-09-29; the audit script used `yaml.safe_load` on each note's frontmatter). Not added this session because the script is Oscar-approved tooling and the change wasn't asked for.



## 2026-09-30 — Internships split into their own vault (Oscar's request)

Oscar asked for everything internship-related to move out of Second Brain into a separate vault and Claude Project. He chose `~/Library/Mobile Documents/com~apple~CloudDocs/Internships` and to move all four standalone careers tasks.
**Moved out** (copied byte-identical to the new vault, then originals moved to `.trash/internships-split-20260930/`): `Internships/` (163 notes, `internships.base`, `.space/`), `Admin/Templates/Claude/Internship Template.md`, and `TaskNotes/Tasks/` Black Rock Interview, Rosthchild Assesment, Register for Edinburgh Award for Employability and Leadership Intro, Register for Sustainable Futures Green Job Career Readiness Workshop. Full pre-split backup: `.internships-split-backup-20260930/`.
**Updated here:** `verify-vault.py` (Internships removed from FOLDERS), AGENTS.md (owner line, seven folders, 10 templates, Internship schema/naming/priority/careers context/§12 row removed), VAULT-INDEX.md (486 notes, 7 types), open-items.md (#6 internship backfill and #13 Rothschild task handed to the new vault), a note at the top of `Admin/Guides/TaskNotes Guide.md`.
**Deliberately not touched:** `TaskNotes/Views/kanban-default.base` still has an `internships.base` branch (Views are not ours to edit; it just matches nothing now); the draft `Weekly Summary Template.md` still has a Careers section (a draft, Oscar's call); lecture/tutorial notes that merely mention the word "internship". No coursework note linked to an internship note, so no links broke.
How to apply: internship, CV, cover letter and careers-event material goes to the Internships vault, not here. The daily Claude/ sort should route careers items there (or flag them) rather than create them in Second Brain.

## 2026-09-30 — Filled `course` on 13 course-less readings; repointed I&E L11 Osterwalder link (Oscar: "fix")

Oscar asked for the audit fixes. Filled `course:` on 13 of the 15 readings in open-items #2, each from the course of the lecture in its own `related` field (BRM2 L10 → Bell ×2, Goulding, Kozinets; I&E L12/L14/L16 → Osterwalder 2011, Chesbrough, Doctorow, Cumming & Johan, Hoffman; PfaS L01 → McKelvey, Barnes, Foroohar). `Osterwalder et al. (2014)` is related to both I&E L12 and PfaS L01; set to Innovation and Enterprise (L12 is the Value Proposition lecture, the book's own subject). Left the two `Wikipedia (2025) - 2025–26 UEFA Champions League…` readings course-less (no related lecture; likely research for a project). Added BRM2, I&E and PfaS views to `Readings/Readings.base` (first readings for those courses; §8). make.md `Readings/.space/views.mdb` NOT updated (needs Obsidian closed) — see open-items #7. Closed open-items #4 (L11 now links `[[Osterwalder et al. (2014) - Value Proposition Design]]`). Backup: `.readings-course-backup-20260930/`. Verified: only `course:` lines changed; verify-vault 0 FAIL, 42 WARN (was 56).

## 2026-10-01 — Claude/Unsorted sort, sixth pass (Oscar: "sort through unsorted")

Scope: `Claude/Unsorted/` only (Inbox and the `OneDrive/{Course}/Unsorted/` folders not touched). Backup: `.unsorted-fold-backup-20261001/` (tray, TEM L02, TEM course note).
- `Week 2 - Failure - TEM - 2026-27 [STUDENTS].pdf` (64 slides, title "Week 2: Failure", Dr Samuel Mwaura) → [[The Entrepreneurial Manager L02 - Lecture 2]] (2026-09-30 09:00). Filed to `Resources/The Entrepreneurial Manager/Slides/lecture-02-failure-2026-09-30.pdf` (md5-verified) and linked in `resources`. Filled every section from the full deck under §12. Image-only slides (charts, screenshots, CB Insights table) were viewed, not just text-extracted. Notes are in the plain style inside the callout. `summary` (quoted, since it holds a colon), `related` → L01. Slides 3–17 are a "But first…" recap that finishes Week 1 (resource mobilisation), so they're in L02 with a pointer, and L01 wasn't edited. The cited references (Clough et al. 2019, flagged "in reading list"; Eisenmann 2021; Yamakawa et al. 2015; others) are listed in the note, but no Reading notes were created because no PDFs were given (same call as L01). Course note Key dates gained two lines from slide 63: FeedbackFruits groupwork (no date) and tutorials start Week 3 with attendance taken.
- Placeholder title kept as `Lecture 2` even though the title slide gives "Failure". Every TEM/MSOA/SM lecture so far kept its `Lecture N` placeholder, so renaming one alone would be inconsistent. Offered to Oscar.
- `Note 2026-09-30 1537/2242/2245.md` (blank copies of the Unsorted template) and `This mornings Lecture.md` (0 bytes; created 08:16 on 2026-09-30, so most likely meant for TEM L02) had nothing to fold in. All moved, along with the original PDF, to `.trash/Unsorted-cleared-20261001/`.
- `creds.txt` is no longer in `Claude/Unsorted/` (open-items #11 updated).
`verify-vault.py`: 0 FAIL, 42 WARN (unchanged); both edited notes' frontmatter parses with `yaml.safe_load`.

## 2026-10-01 — Admin/ and Claude/ replaced by Unsorted/, Agents/ and Templates/ (Oscar's request)

Oscar asked to reorganise `Claude/` and `Admin/` into an Unsorted folder and an Agents folder with a subfolder per agent (the Second Brain app's five agents), and chose a top-level `Templates/`.
**Moved:** `Claude/Unsorted/` → `Unsorted/`; `Admin/Claude/*` → `Agents/`; `Admin/Templates/` → `Templates/`; `Admin/Guides/` → `Templates/Guides/`; `Claude/Inbox/Calendar Sync.md` and `Learn.md` → `Agents/Planner/`; `Claude/Claude outputs/` reading list, notes and script → `Agents/Librarian/`, `Claude/Ellevenread/` → `Agents/Librarian/Ellevenread/`; `second-brain-project-instructions.md` → `Agents/`. New empty `Agents/{Sorter,Scribe,Tutor}/`. Leftover Finder `Icon` files, `.DS_Store` and make.md `.space/` stubs → `.trash/agents-reorg-20261001/`. Backup of both old folders and the touched Obsidian configs: `.agents-reorg-backup-20261001/`.
**Updated:** paths in AGENTS.md, CLAUDE.md, VAULT-INDEX.md, open-items.md, verify-vault.py (now also allows `Templates/Guides/`), project instructions, two templates, TaskNotes Guide, the reading list; Obsidian's template folder, calendar-importer path, TaskNotes excluded folders and make.md paths. Earlier entries in this file were left with their original paths (history).
How to apply: intake is `Unsorted/`; rules are in `Agents/`; an agent's own outputs go in `Agents/{Agent}/`. The scheduled sort routine's prompt (outside the vault) still needs its `Claude/Unsorted` path changed.

## 2026-10-01 — Agents/ split into Course Agents/ and Helper Agents/, one folder per agent (Oscar's request)

**Decided:** `Agents/` keeps the shared files at the top (`AGENTS.md`, `CLAUDE.md`, `VAULT-INDEX.md`, `memory.md`, `open-items.md`, `verify-vault.py`). Below them: `Course Agents/{MSOA,Strategy,TEM}/` and `Helper Agents/{Sorter,Scribe,Librarian,Planner,Tutor}/`.
**Moved:** `Agents/{Sorter,Scribe,Librarian,Planner,Tutor}/` → `Agents/Helper Agents/…` (so `Calendar Sync.md` and `Learn.md` are now under `Agents/Helper Agents/Planner/`). Backup of the old folders: `.agents-folders-backup-20261001/`.
**Updated paths in:** `AGENTS.md`, `VAULT-INDEX.md`, `Templates/Claude/Weekly Summary Template.md`, the Librarian's reading list, and the University Brain app. Older entries in this log keep the old paths on purpose.
**Not touched:** the Calendar Importer plugin's `calendarNotePath` still points at `Agents/Planner/Calendar Sync.md` (plugin settings are not edited without asking). The app now does the calendar sync itself, so the plugin can be switched off, or its path changed, before Obsidian's next sync recreates the old file.

## 2026-10-01 — Agent-specific rules moved into each agent's folder (Oscar's request)

**Decided:** `AGENTS.md` stays the vault's spec and shared rules (session protocol, layout, hard rules, schemas, naming, registry, vocabularies, Bases, files vs notes, checklist, sync hazards). What is specific to one agent moved into that agent's own file, `{Name} agent.md` (course agents: `{Course} course agent.md`), in its folder under `Helper Agents/` or `Course Agents/`.
**Moved:** §11 Tasks → Planner (a short rule stays in §11: the `task` tag, the 3.3 exception, never edit `TaskNotes/Views`). §12 *Filling notes from attachments*: the shared procedure stays (item numbers unchanged), the per-attachment extraction rows went to Scribe, Planner, Librarian and Tutor, item 6 (propagate dates) to Planner, items 9–10 (lecture Notes format, undelivered lectures) to Scribe. §13 Sort Now → Sorter. From `open-items.md`: Readings gaps (1–3) → Librarian; template backfill and lecture restyle (6) → Scribe; file-store gaps (9) and the exposed credentials (11) → Sorter; the Strategic Management and Entrepreneurial Manager date and file questions → their course agents; the `Upload Lecture Slides` task → Planner. Shared items stay in `open-items.md` with a pointer list.
**Not moved:** `memory.md` stays whole (it is append-only history); each agent file lists, by heading, the entries that apply to it. Backup of the old documents: `.agents-docs-backup-20261001/`.
**How to apply:** a session starts with `VAULT-INDEX.md` → `AGENTS.md` → `open-items.md` → newest `memory.md` → its own agent file (`AGENTS.md` §0 step 1). The University Brain app's agents read their own file too.

## 2026-10-01 — Shared agent files moved into `Agents/Shared Agents/` (Oscar's request)

**Decided:** the six files every agent uses now live together in `Agents/Shared Agents/`: `AGENTS.md`, `CLAUDE.md`, `VAULT-INDEX.md`, `memory.md`, `open-items.md`, `verify-vault.py`. `Agents/` itself holds only `Shared Agents/`, `Course Agents/` and `Helper Agents/`.
**Why it matters:** older entries in this log (and any older note or prompt) say `Agents/AGENTS.md`, `Agents/memory.md` etc. Read those as `Agents/Shared Agents/…`. `verify-vault.py` now finds the vault two levels up; run it as `python3 "Agents/Shared Agents/verify-vault.py"`. `CLAUDE.md` imports `@AGENTS.md` from its own folder.
**Updated:** paths in the shared files, every agent file, the Readings template and the TaskNotes guide, and the University Brain app. Backup of the old files: `.agents-shared-backup-20261001/`.
**Check outside the vault:** anything that points at the old locations (a Claude project instruction, a shortcut) must be updated by Oscar.


---

## 2026-10 — Writer and Manager agents

**Added a Writer helper (essay and project coaching) and a Manager that routes requests and sets effort.**
Why: nothing owned essays and projects after Planner filled the brief, and every agent run used the same model regardless of how hard the task was. Writer starts where Planner stops and only fills Thesis, Outline, Evidence plan and Sources (plus `summary`, `readings`, `references`); it coaches and never writes the submission. The Manager picks agent and effort (quick / standard / deep) from keyword rules, then the on-device model; it routes only and changes none of the safety rules.
How to apply: see `Helper Agents/Writer/Writer agent.md` and `Manager Agent/Manager agent.md` (Oscar moved the Manager out of Helper Agents on 2026-10-01: it routes and assigns work rather than being a helper). Writer is on demand, not Autopilot.

---

## 2026-10 — Report outline added to the Project template

**`Templates/Claude/Projects Template.md` gained a `🧱 Report outline` section (Section / Purpose / Words table), before Working notes.**
Why: Essays have an Outline section but Projects had none, so Writer could not plan a project the way it plans an essay, and the Manager could not start it on its own. Existing project notes are unchanged (no backfill); only new ones get the section.
How to apply: Writer fills it from the brief, marking criteria and Oscar's notes, as for an essay Outline.

## 2026-10 — More autonomy for the agents

**Reversible jobs run without a tick, the Manager follows the real Claude budget, agents chain, and they learn from Oscar's edits (`AGENTS.md` §14).**
Why: ticking every routine job slowed things down for no safety gain; every one of these can be put back (old text in `.history/`, originals in `.trash/`, one-tap Undo in the Activity Log). Writer's plans and anything that rewrites Oscar's own lines still wait for a tick.
How to apply: read `## Learned from Oscar's edits` in your own file at the start of each job. Planner now fills blank briefs, Librarian can search the web to find a missing source, Tutor makes a revision set after a lecture is written up; each agent may write in its own folder when chatting.

## 2026-10 — Researcher agent and the `Research/` folder

**A seventh helper, Researcher, and an eighth note folder, `Research/`, for sourced research briefs (`Templates/Claude/Research Template.md`, `Research.base`, naming `{Course} - Research - {Topic}`).**
Why: the heaviest assessments are individual and need evidence from outside the lecture notes (SM Individual Report 70%, TEM reflective report 60%, MSOA Individual Case Study 30%), and no agent answered an open question with sources: Librarian checks specific citations, Writer works from Oscar's own notes.
How to apply: Researcher gathers and summarises with a link for every claim and never drafts submission text; Librarian files its good sources as Readings; Writer cites the Readings. The folder is new, so the seven-folder wording in older entries means the seven before 2026-10-02.

## 2026-10 — The Manager-centred model, the Analyst, and the Manager's office

**The Manager is the only agent that looks for work; it picks a helper and consults the relevant course agent(s); the helper does the job with no approval; the Manager checks the result and undoes it if it fails (`AGENTS.md` §14, `Manager Agent/Manager agent.md`, `Agent Roster.md`).**
Why: ticking every plan slowed things down, and the safety that mattered (staying in scope, keeping Oscar's lines and the template, links that open, one-tap undo) can be checked by the app instead. The Manager runs on the Mac only (no Claude); helpers and course agents run on Claude. New helper **Analyst** (formative maths and data only); `Course briefing.md` per course agent; 22 jobs and checks; budget preset, quiet hours, pause and per-job switches in the Manager menu.
How to apply: do only the job you are given; don't wait for a tick; don't start work yourself; expect to be reviewed and, once, sent back.
