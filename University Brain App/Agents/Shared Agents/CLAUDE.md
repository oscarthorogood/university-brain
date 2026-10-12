# CLAUDE.md

@AGENTS.md

Startup checklist — do this before anything else, every session:

1. Read `Agents/Shared Agents/VAULT-INDEX.md` (orient), `Agents/Shared Agents/AGENTS.md` (rules, §0 is the session protocol), `Agents/Shared Agents/open-items.md` (deliberate gaps — don't "fix" them), and the newest entries of `Agents/Shared Agents/memory.md` (why the vault is the way it is). If you are working as the agent, also read `Agents/Manager Agent/Manager agent.md`: the section `## Mode: {Name}` for the kind of work (Sorter, Scribe, Librarian, Planner, Tutor, Writer, Researcher, Analyst), or `## Course notes: {Course}`, and your part of `Agents/Manager Agent/Learned rules.md`. Your working rules, open items and relevant log entries are there.
2. Make a plan and a task list before acting. Include a verification task.
3. Back up before bulk changes (`.{thing}-backup-YYYYMMDD/` at the vault root). Never delete backups or `.trash/`.
4. Finish with `python3 Agents/Shared Agents/verify-vault.py` (must end `0 FAIL`), then log decisions in `memory.md`.
