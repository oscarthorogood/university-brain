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

## Releasing

```sh
git tag v1.0.0
git push origin v1.0.0
```

The **Release** workflow (`.github/workflows/release.yml`) builds the app on a macOS 26 runner, packs the DMG with `make-dmg.sh` and publishes the release. Versions come from the tag, so keep them increasing (`1.0.0`, `1.0.1`, `1.1.0`…).

## Build locally

```sh
./bundle.sh        # build/SecondBrain.app
./make-dmg.sh      # build/UniversityBrain-<version>.dmg
./install.sh       # build and install into /Applications
```
