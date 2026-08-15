#!/usr/bin/env bash
# Builds the installable addon: dist/Refactor/ plus a zip of it.
#
# The folder name is load-bearing and must be exactly "Refactor" -- the
# client finds a .toc only when it matches its folder's name, and the code
# hardcodes asset paths like Interface\AddOns\Refactor\textures\... A
# repository checkout named anything else (this fork's folder included)
# will silently load nothing, so the build renames rather than assumes.
#
# Usage:  tools/package.sh          # build dist/Refactor and the zip
#         tools/package.sh --check  # verify only, build nothing
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/dist"
NAME="Refactor"
STAGE="$OUT/$NAME"

# Everything the client actually loads or reads by path, plus the docs the
# MIT notice travels with. Deliberately excluded: tests/ (not in the .toc,
# never loaded), docs/ (5 MB of README screenshots), refactor.jpg (a promo
# image -- 3.3.5 cannot load .jpg textures at all), and the repository
# plumbing.
CONTENTS=(
    "Refactor.toc"
    "RefactorCC.lua" "RefactorFog.lua" "RefactorMap.lua"
    "RefactorToast.lua" "RefactorUI.lua"
    "modules" "RefactorCompare"
    "arrow.tga" "refactor.tga" "textures" "sounds"
    "client-patch"
    "LICENSE" "README.md" "CHANGELOG.md"
)

VERSION="$(sed -n 's/^## Version:[[:space:]]*//p' "$ROOT/Refactor.toc" | tr -d '\r')"
[ -n "$VERSION" ] || { echo "no '## Version:' line in Refactor.toc" >&2; exit 1; }

# Every file the .toc lists must exist, or the addon loads half of itself
# and errors at the first cross-file reference. (This is exactly how the
# repository shipped before the subfolders were restored.)
missing=0
while read -r entry; do
    file="$(printf '%s' "$entry" | tr -d '\r' | tr '\\' '/')"
    [ -n "$file" ] || continue
    if [ ! -f "$ROOT/$file" ]; then
        echo "MISSING (listed in Refactor.toc): $file" >&2
        missing=1
    fi
    # The .toc carries a UTF-8 BOM, which otherwise sticks to the first
    # line and hides its leading "##" from the directive filter.
done < <(sed '1s/^\xEF\xBB\xBF//' "$ROOT/Refactor.toc" | tr -d '\r' | grep -vE '^\s*(##|#|$)')
[ "$missing" -eq 0 ] || exit 1

# Lua syntax gate, so a typo can never reach a zip. luac is optional --
# skipped with a note rather than failing the build if it isn't installed.
if command -v luac5.1 >/dev/null 2>&1; then LUAC=luac5.1
elif command -v luac >/dev/null 2>&1; then LUAC=luac
else LUAC=""; fi
if [ -n "$LUAC" ]; then
    while IFS= read -r f; do
        "$LUAC" -p "$f" || { echo "syntax error: $f" >&2; exit 1; }
    done < <(find "$ROOT/modules" "$ROOT/RefactorCompare" -name '*.lua'; ls "$ROOT"/*.lua)
    rm -f "$ROOT/luac.out"
    echo "syntax OK (all Lua files, $LUAC)"
else
    echo "note: no luac found, skipping the syntax check"
fi

if [ "${1:-}" = "--check" ]; then
    echo "checks passed for v$VERSION"
    exit 0
fi

rm -rf "$STAGE"
mkdir -p "$STAGE"
for item in "${CONTENTS[@]}"; do
    [ -e "$ROOT/$item" ] && cp -r "$ROOT/$item" "$STAGE/"
done

ZIP="$OUT/$NAME-$VERSION.zip"
rm -f "$ZIP"
( cd "$OUT" && zip -qr "$(basename "$ZIP")" "$NAME" )

echo
echo "built  $ZIP"
echo "       $(du -sh "$STAGE" | cut -f1) unpacked, $(du -h "$ZIP" | cut -f1) zipped"
echo "       extracts to Interface/AddOns/$NAME/"
