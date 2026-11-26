#!/bin/bash
# Writes apple/OpenTodo.xcodeproj from apple/project.yml.
set -euo pipefail
APPLE="$(cd "$(dirname "$0")/.." && pwd)"
XCODEGEN="$(command -v xcodegen || echo /opt/homebrew/bin/xcodegen)"
cd "$APPLE"
"$XCODEGEN" generate --spec project.yml --quiet
echo "$APPLE/OpenTodo.xcodeproj"
