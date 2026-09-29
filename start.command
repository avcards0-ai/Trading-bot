#!/bin/bash
# Double-click to start MemeGuard on macOS (installs on first run, then opens the dashboard).
cd "$(dirname "$0")" || exit 1

if ! command -v node >/dev/null 2>&1; then
  echo "MemeGuard needs Node.js, which is not installed on this computer."
  echo "Opening the Node.js download page. Install the LTS version,"
  echo "then double-click start.command again."
  open "https://nodejs.org/en/download" 2>/dev/null || xdg-open "https://nodejs.org/en/download" 2>/dev/null
  read -r -p "Press Enter to close this window."
  exit 1
fi

node scripts/start.mjs || read -r -p "Press Enter to close this window."
