#!/bin/bash
# Renames the app everywhere: module and folder names, source, docs and bundle script.
#   scripts/rename-app.sh Heft
# Use one capitalised word (it becomes a Swift module name).
set -euo pipefail
NEW="${1:-}"
OLD="Pantry"
if [[ -z "$NEW" || ! "$NEW" =~ ^[A-Z][A-Za-z0-9]*$ ]]; then
  echo "usage: scripts/rename-app.sh NewName   (one capitalised word, letters and digits only)" >&2
  exit 1
fi
cd "$(dirname "$0")/.."
NEW_LOWER="$(printf '%s' "$NEW" | tr '[:upper:]' '[:lower:]')"

# 1. File contents (skips .git, build output and this script).
grep -rIl --exclude-dir=.git --exclude-dir=.build --exclude-dir=dist --exclude=rename-app.sh -e "$OLD" -e "pantry" . \
  | while IFS= read -r file; do
      perl -pi -e "s/Pantry/${NEW}/g; s/pantry/${NEW_LOWER}/g" "$file"
    done

# 2. Folder and file names, deepest first.
find . -depth \( -path ./.git -o -path ./.build -o -path ./dist \) -prune -o -name "*${OLD}*" -print \
  | while IFS= read -r path; do
      dir="$(dirname "$path")"; base="$(basename "$path")"
      mv "$path" "${dir}/${base//${OLD}/${NEW}}"
    done

echo "Renamed ${OLD} -> ${NEW}. Run: swift build && swift test"
