## How to organise the Resources folder

The `Resources` folder does not contain markdown notes — it holds the actual source files (PDFs, slide decks, datasets, images, recordings, etc.) that Lecture, Essay, Project, Reading, and Revision notes point to via their `resources` field.

- Organise by course first, then by type: `Files/Resources/{Course Name}/{file type}/`, e.g. `Files/Resources/Introduction to AI/Slides/`, `Files/Resources/Introduction to AI/Datasets/`. Every resource belongs under its course folder — there should be no course-related files sitting loose at the top level of `Resources`.
- For resources that aren't tied to a specific course (general references, personal templates, tools), use `Files/Resources/General/{file type}/`.
- Never store working drafts or files still being edited here — this folder is for finished, reference-only material. Active working files belong on OneDrive and should be linked via the `onedrive` field instead.
- Every file placed here should be linked from at least one note's `resources` field; if nothing links to it, it likely doesn't belong in the vault.
- Keep the folder flat within each type subfolder — avoid deep nesting beyond `Files/Resources/{Course}/{type}/`, so files stay easy to browse and link.
- When a resource is superseded (e.g. a new version of a slide deck), replace the file in place rather than keeping both, and update the filename per the naming conventions note.

## Pulling detail from files into notes

Files hold the detail; notes hold what matters from them. Whenever a file is linked from a note, read it and extract into that note:

- **Slides** → lecture structure, learning objectives, definitions, frameworks, formulas, examples, references cited, announcements.
- **Briefs and rubrics** → question (verbatim), weighting, word limit, deadline, submission rules, marking criteria.
- **Exemplars** → structure used, what earned marks, what to avoid.
- **Tutorial sheets and solutions** → questions (verbatim) and model answers.
- **Past papers, mark schemes, examiner reports** → questions, marks, examiner comments.
- **Readings (PDFs)** → verified citation, structure, argument, method, findings, definitions, quotes — each with a page number.
- **Spreadsheets and data** → what the file contains (sheets, variables, period) and which question it serves.

Rules: cite the location (`slide 12`, `p. 4`, `Sheet "Data"`); summarise rather than paste; copy only questions, briefs and quotes verbatim; leave a field blank rather than guess; match a file to its course by content, not filename.
