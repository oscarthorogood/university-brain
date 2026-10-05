#!/usr/bin/env python3
"""Second Brain vault verifier.

Run from anywhere:  python3 "<vault>/Agents/Shared Agents/verify-vault.py"   (or pass the vault path as argv[1])
Read-only. Prints counts, then FAIL lines (rule breaks) and WARN lines (known/possible gaps).
Exit code 1 if any FAIL.
"""
import os, re, sys, collections

VAULT = sys.argv[1] if len(sys.argv) > 1 else os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
os.chdir(VAULT)

STUDY = ['MCQ', 'Flashcards', 'Past Papers', 'Summaries', 'Mind Maps', 'Glossary', 'Podcast']   # Revision was split into these
NOUN = {'MCQ': 'MCQ', 'Flashcards': 'Flashcards', 'Past Papers': 'Past Paper', 'Summaries': 'Summary', 'Mind Maps': 'Mind Map', 'Glossary': 'Glossary', 'Podcast': 'Podcast'}
STUDY_TYPES = {'MCQ': {'MCQ Test', 'Quiz'}, 'Flashcards': {'Flashcards'}, 'Past Papers': {'Past Paper', 'Exam'}, 'Summaries': {'Summary', 'Handout', 'Code'},
               'Mind Maps': {'Mind Map'}, 'Glossary': {'Glossary'}, 'Podcast': {'Podcast'}}
READING_TYPES = {'Research Source', 'Course Reading'}


FOLDERS = {  # folder: (template file, base file)
    'Courses': ('Course', 'Courses.base'),
    'Lectures': ('Lecture', 'Lectures.base'),
    'Readings': ('Readings', 'Readings.base'),
    'Tutorials': ('Tutorial', 'Tutorials.base'),
    'Essays': ('Essay', 'Essays.base'),
    'Projects': ('Projects', 'Projects.base'),
    'MCQ': ('MCQ', 'MCQ.base'),
    'Flashcards': ('Flashcards', 'Flashcards.base'),
    'Past Papers': ('Past Paper', 'Past Papers.base'),
    'Summaries': ('Summary', 'Summaries.base'),
    'Mind Maps': ('Mind Map', 'Mind Maps.base'),
    'Glossary': ('Glossary', 'Glossary.base'),
    'Podcast': ('Podcast', 'Podcast.base'),
    'Research': ('Research', 'Research.base'),
}
LOC = {'Lectures': 'Items/Lectures', 'Readings': 'Items/Readings', 'Tutorials': 'Items/Tutorials', 'Essays': 'Items/Essays', 'Projects': 'Items/Projects'}
# Summaries, Past Papers, Mind Maps and Research live in Files/, the other study folders in Apps/; a vault not yet moved may still have them in Apps/
for _k in [*STUDY, 'Research']:
    _home = 'Files' if _k in ('Summaries', 'Past Papers', 'Mind Maps', 'Research') else 'Apps'
    LOC[_k] = f'{_home}/{_k}' if os.path.isdir(f'{_home}/{_k}') or not os.path.isdir(f'Apps/{_k}') else f'Apps/{_k}'  # Courses is top-level
ALLOWED_EXTRA_KEYS = {'dateModified', 'completedDate'}  # TaskNotes exception (AGENTS.md 3.3)
STATUS = {'Not started', 'In Progress', 'Done'}
fails, warns = [], []
def fail(m): fails.append(m)
def warn(m): warns.append(m)

def fm_of(text):
    m = re.match(r'---\n(.*?)\n---', text, re.S)
    return m.group(1) if m else None

def keys_of(fm):
    return [l.split(':')[0] for l in fm.split('\n') if re.match(r'^[A-Za-z_][^:]*:', l)]

def val(fm, key):
    m = re.search(rf'^{re.escape(key)}: *(.*)$', fm, re.M)
    return m.group(1).strip().strip('"') if m else None

courses = sorted(f[:-3] for f in os.listdir('Courses') if f.endswith('.md'))
titles = {}
counts = {}
for folder, (tname, base) in FOLDERS.items():
    tpath = next((p for g in ('', 'Items/', 'Files/', 'Apps/') if os.path.exists(p := f'Templates/Claude/{g}{tname} Template.md')), f'Templates/Claude/{tname} Template.md')   # grouped by Items/Files/Apps; flat copies still count
    tk = keys_of(fm_of(open(tpath, encoding='utf-8').read()))
    d = LOC.get(folder, folder)
    entries = os.listdir(d)
    counts[folder] = 0
    if not os.path.exists(f'{d}/{base}'):
        fail(f'{d}: missing {base}')
    for e in sorted(entries):
        p = f'{d}/{e}'
        if os.path.isdir(p):
            if e.startswith('.'):
                continue  # app config such as .space/
            fail(f'{p}: folder nested inside flat note folder')
            continue
        if not e.endswith('.md'):
            continue
        counts[folder] += 1
        name = e[:-3]
        titles.setdefault(name.lower(), []).append(p)
        t = open(p, encoding='utf-8').read()
        fm = fm_of(t)
        if fm is None:
            fail(f'{p}: no frontmatter'); continue
        k = keys_of(fm)
        k_core = [x for x in k if x not in ALLOWED_EXTRA_KEYS]
        if k_core != tk:
            fail(f'{p}: frontmatter differs from template (extra {sorted(set(k_core)-set(tk))}, missing {sorted(set(tk)-set(k_core))}, or order)')
        if val(fm, 'base') != f'[[{base}]]':
            fail(f'{p}: base is {val(fm, "base")!r}, want [[{base}]]')
        st = val(fm, 'status')
        if st not in STATUS:
            (warn if (folder == 'Readings' and st == 'To Find') else fail)(f'{p}: status {st!r}')
        if re.search(r'[\\/:*?"<>|]', name):
            fail(f'{p}: forbidden character in title')
        if folder not in ('Courses', 'Internships'):
            key = 'Course' if folder in STUDY else 'course'
            c = re.search(rf'^{key}: "\[\[(.*?)\]\]"', fm, re.M)
            if not c:
                (warn if folder == 'Readings' else fail)(f'{p}: no {key}')
            elif c.group(1) not in courses:
                fail(f'{p}: {key} [[{c.group(1)}]] is not a course')
            else:
                cn = c.group(1)
                pat = {'Lectures': rf'^{re.escape(cn)} L\d{{2}} - .+',
                       'Tutorials': rf'^{re.escape(cn)} T\d{{2}} - .+',
                       'Essays': rf'^{re.escape(cn)} - Essay( \d+)? - .+',
                       'Projects': rf'^({re.escape(cn)} - Project - .+|.+)',
                       **{k: rf'^{re.escape(cn)} - (Revision|{re.escape(NOUN[k])}) - .+' for k in STUDY},
                       'Research': rf'^{re.escape(cn)} - Research - .+'}.get(folder)
                if pat and not re.match(pat, name):
                    warn(f'{p}: title does not match naming pattern')
                if folder in ('Lectures', 'Tutorials'):
                    n = re.search(r' [LT](\d{2}) - ', name)
                    field = val(fm, 'Lecture No.' if folder == 'Lectures' else 'Tutorial No.')
                    if n and field and field.isdigit() and int(field) != int(n.group(1)):
                        warn(f'{p}: number field {field} != title number {n.group(1)}')
        if folder == 'Readings':
            ty = val(fm, 'type')
            if ty not in READING_TYPES:
                fail(f'{p}: reading type {ty!r}')
        if folder in STUDY:
            ty = val(fm, 'type')
            if ty not in STUDY_TYPES[folder]:
                fail(f'{p}: {folder} type {ty!r}')
        for lm in re.findall(r'^\s+- "\[\[(.*?)\]\]"', fm, re.M) + re.findall(r'^(?:course|Course|related|references): "\[\[(.*?)\]\]"', fm, re.M):
            tgt = lm.split('|')[0].split('#')[0]
            if '/' in tgt or re.search(r'\.[A-Za-z0-9]{2,5}$', tgt) and not re.search(r'\.\s', tgt) and not re.search(r'\((\d{4})\)', tgt) and tgt.rsplit('.', 1)[-1].lower() in ('pdf', 'ppt', 'pptx', 'png', 'jpg', 'jpeg', 'xlsx', 'xls', 'docx', 'doc', 'csv', 'zip', 'mp4', 'mp3', 'py', 'ipynb', 'base', 'txt', 'json', 'html'):
                continue  # file links (resources / onedrive) are checked by file existence elsewhere
            if tgt.lower() not in {n2 for n2 in titles} and not any(
                    os.path.exists(f'{LOC.get(f2, f2)}/{tgt}.md') for f2 in list(FOLDERS) + ['Items/Assignments']):
                if not (tgt.endswith('.base')):
                    warn(f'{p}: link [[{tgt}]] does not resolve to a note')

for name, paths in titles.items():
    if len(paths) > 1:
        fail(f'duplicate title across folders: {paths}')

# Templates folder holds templates only
for f in os.listdir('Templates'):
    if f not in ('Claude', 'Human', 'Guides', '.DS_Store'):
        fail(f'Templates/{f}: only Claude/, Human/ and Guides/ belong here')
# Required admin files
for f in ('AGENTS.md', 'CLAUDE.md', 'VAULT-INDEX.md', 'memory.md', 'open-items.md'):
    if not os.path.exists(f'Agents/Shared Agents/{f}'):
        fail(f'Agents/Shared Agents/{f} missing')

print('COUNTS', ' '.join(f'{k}={v}' for k, v in counts.items()), f'total={sum(counts.values())}', f'courses={len(courses)}')
for w in warns: print('WARN', w)
for f in fails: print('FAIL', f)
print(f'{len(fails)} FAIL, {len(warns)} WARN')
sys.exit(1 if fails else 0)
