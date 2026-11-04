#!/usr/bin/env bash
# Runs every offline Lua test: spells, all script types (tfs NPCs) and the crystal NPCs.
# Usage (from the server root): tests/lua/run-script-tests.sh [-v|-t] [filter]
set -u
cd "$(dirname "$0")/../.."
api=$(mktemp --suffix=.lua)
trap 'rm -f "$api"' EXIT
python3 tools/generate-lua-api.py > "$api" || exit 2
spellArgs=()
for a in "$@"; do [ "$a" = -v ] || [ "$a" = -t ] || spellArgs+=("$a"); done
status=0
echo "######## spells"
lua5.4 tests/lua/spells_test.lua "$api" "${spellArgs[@]}" || status=1
echo "######## scripts (npcSystem tfs)"
lua5.4 tests/lua/scripts_test.lua "$api" tfs "$@" || status=1
echo "######## npcs crystal"
lua5.4 tests/lua/scripts_test.lua "$api" crystal "$@" || status=1
exit $status
