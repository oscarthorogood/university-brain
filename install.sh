#!/bin/sh
# Builds the app, quits the running copy, moves the old one to the Trash and installs the new one.
set -e
cd "$(dirname "$0")"
./bundle.sh
osascript -e 'tell application "University Brain" to quit' 2>/dev/null || true
sleep 2
[ -d "/Applications/University Brain.app" ] && mv "/Applications/University Brain.app" "$HOME/.Trash/University Brain (old $(date +%H%M%S)).app"
cp -R build/SecondBrain.app "/Applications/University Brain.app"
open "/Applications/University Brain.app"
echo "Installed."
