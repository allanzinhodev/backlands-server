#!/usr/bin/env bash
# Offline spell tests: dump the engine's Lua API from src/ and run every spell against the mock.
# Usage (any dir): tests/lua/run-spell-tests.sh [filter]   (filter = part of the file path or spell name)
set -euo pipefail
cd "$(dirname "$0")/../.."
api="$(mktemp --suffix=.lua)"
trap 'rm -f "$api"' EXIT
python3 tools/generate-lua-api.py > "$api"
lua5.4 tests/lua/spells_test.lua "$api" "$@"
