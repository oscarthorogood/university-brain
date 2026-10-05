# University Brain

A macOS 26 app over an Obsidian vault of university notes (see `HANDOFF.md` and `PLAN.md`).

## Install

Download the latest `UniversityBrain-<version>.dmg` from [Releases](https://github.com/oscarthorogood/university-brain/releases/latest), open it and drag **University Brain** to **Applications**.

The app is not notarised (it has no Developer ID), so the first time macOS says it can't check it for malicious software. Open it once, then go to **System Settings → Privacy & Security** and click **Open Anyway**. Or, in Terminal:

```sh
xattr -dr com.apple.quarantine "/Applications/University Brain.app"
```

## Updates

The arrow icon next to Settings, at the top left of the window, checks GitHub for a newer release. The app also checks shortly after launch and every six hours, and the icon fills in when one is waiting. **Install and Relaunch** downloads the new DMG, checks its SHA-256, swaps the app in place (the old one goes to the Trash) and reopens it. Updates installed this way don't need **Open Anyway** again.

## Templates and Agents

The `University Brain App/` folder in this repo holds the vault's `Templates/` and `Agents/` files. `bundle.sh` packs it into the app, and the first time each new version runs it copies the folder into the vault (`~/Documents/University`, or the folder chosen in Settings), so the templates and the agents' instructions always match the installed version.

- It **overwrites**: a shipped file that differs from the vault's is replaced, and the old text is kept in the vault's `.history/` (the Activity Log notes how many files were updated).
- Files the folder doesn't contain are never touched or deleted. So the folder holds only the shared rules, templates and agent instructions, never your own data: `memory.md`, `open-items.md`, each course's `Course briefing.md`, `Calendar Sync.md`, `Learn.md` and the agents' work products stay out of it, or an update would reset them.
- The agent files (`<Name> agent.md`) are shipped, so anything an agent wrote into its own file is replaced on an update (the old text stays in `.history/`).
- Edits made to the repo's folder go out like any other app change: merging into `main` cuts a release.
- The copy is skipped if the vault folder doesn't exist yet, and tried again on the next launch.

## Releasing

Every merge into `main` that changes the app (`Sources/`, `University Brain App/`, `Package.swift`, `Icon/`, `bundle.sh` or `make-dmg.sh`) cuts a release automatically: the patch number goes up by one (`1.0.3` → `1.0.4`). Edits to docs or the workflow alone don't.

For a bigger jump, use **Actions → Release → Run workflow** and type the version (`1.1.0`, `2.0.0`); later merges count on from there. Pushing a tag such as `v1.1.0` does the same.

The **Release** workflow (`.github/workflows/release.yml`) builds the app on a macOS 26 runner, packs the DMG with `make-dmg.sh` and publishes the release.

## Build locally

```sh
./bundle.sh        # build/SecondBrain.app
./make-dmg.sh      # build/UniversityBrain-<version>.dmg
./install.sh       # build and install into /Applications
```
