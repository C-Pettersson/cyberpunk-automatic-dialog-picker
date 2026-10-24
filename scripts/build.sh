#!/usr/bin/env bash
# Runs the tests and packages the mod into dist/AutoDialogPicker-v<version>.zip
# (game folder layout, ready to extract into the Cyberpunk 2077 folder).
#
#   ./scripts/build.sh            build from the version in init.lua
#   TAG=v1.2.3 ./scripts/build.sh also check that the tag matches that version
#
# Needs: luajit, zip. Set LUAJIT=/path/to/luajit to use another binary.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MOD_REL="bin/x64/plugins/cyber_engine_tweaks/mods/AutoDialogPicker"
MOD="$ROOT/$MOD_REL"
LUAJIT="${LUAJIT:-luajit}"
FILES=(init.lua logic.lua AutoDialogPicker-Helper.ahk helper-keys.ini README.txt)

VERSION="$(sed -n 's/^local VERSION = "\(.*\)"$/\1/p' "$MOD/init.lua")"
if [ -z "$VERSION" ]; then
    echo "error: could not read VERSION from init.lua" >&2
    exit 1
fi
echo "Auto Dialog Picker v$VERSION"

if [ -n "${TAG:-}" ] && [ "$TAG" != "v$VERSION" ]; then
    echo "error: tag $TAG does not match init.lua version v$VERSION" >&2
    exit 1
fi
if ! grep -q "v$VERSION" "$MOD/README.txt"; then
    echo "error: README.txt does not mention v$VERSION" >&2
    exit 1
fi
if ! grep -q "^## $VERSION" "$ROOT/CHANGELOG.md"; then
    echo "error: CHANGELOG.md has no '## $VERSION' section" >&2
    exit 1
fi

echo "== syntax"
for f in "$MOD"/*.lua; do
    "$LUAJIT" -e "assert(loadfile('$f'))"
done

echo "== tests"
LUA_PATH="$MOD/?.lua;;" "$LUAJIT" "$ROOT/tests/test_logic.lua"
SIM="$(mktemp -d)"
(cd "$SIM" && "$LUAJIT" "$ROOT/tests/sim.lua" "$MOD")
rm -rf "$SIM"

echo "== package"
DIST="$ROOT/dist"
STAGE="$(mktemp -d)"
rm -rf "$DIST"
mkdir -p "$DIST" "$STAGE/$MOD_REL"
for f in "${FILES[@]}"; do
    cp "$MOD/$f" "$STAGE/$MOD_REL/$f"
done
cp "$ROOT/LICENSE.md" "$STAGE/$MOD_REL/LICENSE.md"
ZIP="$DIST/AutoDialogPicker-v$VERSION.zip"
(cd "$STAGE" && zip -r -X -q "$ZIP" bin)
rm -rf "$STAGE"

# Release notes: the CHANGELOG section for this version
awk -v v="## $VERSION" '
    $0 == v || index($0, v " ") == 1 { on = 1; next }
    on && /^## / { exit }
    on { print }
' "$ROOT/CHANGELOG.md" > "$DIST/release-notes.md"

echo "built $ZIP"
unzip -l "$ZIP"
