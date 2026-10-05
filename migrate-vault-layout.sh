#!/bin/sh
# Splits the vault's Relations/ folder into Apps/ (study tools and research) and Files/ (Zotero, Resources, OneDrive),
# next to the existing Items/, and rewrites the paths written in the vault's own docs. Nothing is deleted:
# the original text of every edited file goes to .relations-split-backup-<date>/, and moves can be undone by moving back.
# Usage: ./migrate-vault-layout.sh [vault folder]   (default ~/Documents/University; try it on a copy first)
set -e
V="${1:-$HOME/Documents/University}"
cd "$V"
[ -d Relations ] || { echo "No Relations/ folder in $V: nothing to do."; exit 0; }
[ ! -e Apps ] && [ ! -e Files ] || { echo "Apps/ or Files/ already exists in $V: not touching it."; exit 1; }
BK=".relations-split-backup-$(date +%Y%m%d)"
mkdir -p "$BK" Apps Files

for f in MCQ Flashcards "Past Papers" Summaries "Mind Maps" Glossary Podcast Research; do [ -d "Relations/$f" ] && mv "Relations/$f" Apps/; done
for f in Resources OneDrive Zotero; do [ -d "Relations/$f" ] && mv "Relations/$f" Files/; done
# Relations/ now holds only Finder's .DS_Store; anything else stays and is reported.
rm -f Relations/.DS_Store
rmdir Relations 2>/dev/null || { echo "Left Relations/ in place, it still holds:"; ls -A Relations; }

# The app's text copies of PDFs and the undo snapshots are keyed by vault path.
if [ -d .pdf-text/Relations ]; then mkdir -p .pdf-text/Files; for f in .pdf-text/Relations/*; do mv "$f" .pdf-text/Files/; done; rmdir .pdf-text/Relations; fi
for h in .history/Relations›*; do
  [ -e "$h" ] || continue
  n="${h#.history/Relations›}"
  case "$n" in Resources›*|OneDrive›*|Zotero›*) to="Files›$n" ;; *) to="Apps›$n" ;; esac
  mv "$h" ".history/$to"
done

# Paths written in docs, templates and the agents' instructions (not .history, .trash or old backups).
FILES=$(grep -rIlE "Relations" Agents Courses Templates Tags Items Apps Files --include="*.md" --include="*.py" --include="*.txt" --include="*.base" 2>/dev/null || true)
echo "$FILES" | while IFS= read -r f; do
  [ -n "$f" ] || continue
  mkdir -p "$BK/$(dirname "$f")"; cp -p "$f" "$BK/$f"
  perl -pi -e '
    s{Relations/(Resources|OneDrive|Zotero)}{Files/$1}g;
    s{Relations/(MCQ|Flashcards|Past Papers|Summaries|Mind Maps|Glossary|Podcast|Research)}{Apps/$1}g;
    s{`Items/` \(work\) and `Relations/` \(revision, research, Zotero, files\)}{`Items/` (work), `Files/` (Zotero, Resources, OneDrive) and `Apps/` (revision tools, research)}g;
    s{the study folders under `Relations/`}{the study folders under `Apps/`}g;
    s{and `Relations/` \(what relates to it:}{and `Apps/` and `Files/` (what relates to it:}g;
    s{\*\*Relations\*\* card}{**Related** card}g;
    s{\*\*Relations\*\* \(}{**Related** (}g;
    s{A Relations note}{An Apps or Files note}g;
    s{what it relates to in `Relations/`}{what it relates to in `Apps/` and `Files/`}g;
    s{\{k: \x27Relations/\x27 \+ k for k in STUDY\}}{{k: \x27Apps/\x27 + k for k in STUDY}}g;
  ' "$f"
done
echo "Moved. Edited docs are backed up in $V/$BK. Remaining mentions (check by eye):"
grep -rnIE "Relations/|Relations\`" Agents Courses Templates Tags Items Apps Files --include="*.md" --include="*.py" --include="*.txt" --include="*.base" 2>/dev/null | cut -c1-200 || true
