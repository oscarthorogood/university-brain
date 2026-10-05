
## Naming Conventions

Consistent titles are what make links, search, and Bases views usable across the vault. Use the patterns below for each note type.

### 1. Course
`{Course Name}`
Example: `Introduction to AI`

### 2. Lecture
`{Course Name} L{Lecture No.} - {Topic}`
Example: `Introduction to AI L03 - Search Algorithms`
Zero-pad the lecture number to two digits so notes sort correctly (`L03`, not `L3`).

### 3. Tutorial
`{Course Name} T{Tutorial No.} - {Topic}`
Example: `Introduction to AI T03 - Search Algorithms Problem Set`
Zero-pad the tutorial number to two digits so notes sort correctly (`T03`, not `T3`).

### 4. Essay
`{Course Name} - Essay - {Short Title}`
Example: `Introduction to AI - Essay - Ethics of Autonomous Agents`
If the course sets a formal essay/assignment number, include it: `{Course Name} - Essay {No.} - {Short Title}`.

### 5. Project
`{Course Name} - Project - {Project Name}` (coursework), or `{Project Name}` (personal/independent projects)
Example: `Introduction to AI - Project - Chatbot Prototype`

### 6. Readings
`{Author Surname} ({Year}) - {Short Title}`
Example: `Russell (2020) - Rationality and Intelligence`
For multiple authors, use `{First Author} et al. ({Year}) - {Short Title}`.

### 7. Study notes (MCQ, Flashcards, Past Paper, Summary, Mind Map, Glossary, Podcast)
`{Course Name} - {Type} - {Topic}`
Example: `Introduction to AI - MCQ - Search Algorithms`
(Notes made before 2026-10-03 keep `- Revision -` in their title.)

### 7b. Research
`{Course Name} - Research - {Topic}`
Example: `Strategic Management - Research - Tesla Strategy 2020s`

### 8. Resources (folder/file organisation, not individual notes)
`{descriptive-name}-{version or date}.{ext}`, stored under `Files/Resources/{Course Name}/{file type}/`
Example: `Files/Resources/Introduction to AI/Slides/lecture-03-search-2026-02-10.pdf`
Use lowercase, hyphen-separated filenames on disk; keep the note-facing description in the linking note's `resources` field human-readable.

### 9. OneDrive (folder/file organisation, not individual notes)
Mirror the vault naming pattern for the corresponding note type, stored under `Files/OneDrive/{Course Name}/{note type}/`
Example: `Files/OneDrive/Introduction to AI/Essays/Introduction to AI - Essay - Ethics of Autonomous Agents.docx`
Keep the OneDrive filename identical (or as close as possible) to the vault note title it's linked from, so the two are easy to match up at a glance.

---

**General rules across all types:**
- Use title case for note titles.
- Avoid special characters (`/ \ : * ? " < > |`) in titles — they break links and cause file-system issues on sync.
- Don't include dates in note titles unless the type is inherently date-based (e.g. Readings, past papers) — dates belong in frontmatter fields so they can be sorted and filtered.
