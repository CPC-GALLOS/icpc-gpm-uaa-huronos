#!/usr/bin/env bash
# =============================================================================
# update-directives-wallpaper.sh — CPC GALLOS / UAA
# Generic tool to calculate wallpaper SHA256 and update any/all .hdf files.
#
# Usage:
#   ./update-directives-wallpaper.sh [wallpaper_file] [directives_file.hdf]
# Examples:
#   ./update-directives-wallpaper.sh                               # Updates all *.hdf files with wallpaper.png
#   ./update-directives-wallpaper.sh my-wallpaper.png             # Updates all *.hdf with my-wallpaper.png
#   ./update-directives-wallpaper.sh wallpaper.png contest.hdf    # Updates contest.hdf with wallpaper.png
#   ./update-directives-wallpaper.sh contest.hdf                  # Updates contest.hdf with default wallpaper.png
# =============================================================================

set -e

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

ARG1="$1"
ARG2="$2"

WALLPAPER_FILE=""
HDF_TARGET=""

# Parse arguments flexibly
if [ -n "$ARG1" ] && [[ "$ARG1" == *.hdf ]]; then
    HDF_TARGET="$ARG1"
    WALLPAPER_FILE="$ARG2"
elif [ -n "$ARG1" ]; then
    WALLPAPER_FILE="$ARG1"
    HDF_TARGET="$ARG2"
fi

# Auto-detect wallpaper file if not explicitly passed
if [ -z "$WALLPAPER_FILE" ] || [ ! -f "$WALLPAPER_FILE" ]; then
    if [ -f "$SCRIPT_DIR/huronos-wallpaper.png" ]; then
        WALLPAPER_FILE="$SCRIPT_DIR/huronos-wallpaper.png"
    elif [ -f "$SCRIPT_DIR/wallpaper.png" ]; then
        WALLPAPER_FILE="$SCRIPT_DIR/wallpaper.png"
    else
        # Find first image file in repo
        FOUND_IMG=$(find "$SCRIPT_DIR" -maxdepth 1 \( -name "*wallpaper*.png" -o -name "*wallpaper*.jpg" -o -name "*wallpaper*.jpeg" \) 2>/dev/null | head -n 1 || true)
        if [ -n "$FOUND_IMG" ]; then
            WALLPAPER_FILE="$FOUND_IMG"
        else
            echo "❌ Error: No custom wallpaper found (looked for huronos-wallpaper.png or wallpaper.png)."
            exit 1
        fi
    fi
fi

echo "============================================="
echo " huronOS Generic Wallpaper & Directives Tool"
echo "============================================="
echo "Target wallpaper: $WALLPAPER_FILE"

FILE_INFO=$(file "$WALLPAPER_FILE")
echo "Format/Type:      $FILE_INFO"

WALLPAPER_SHA=$(sha256sum "$WALLPAPER_FILE" | awk '{print $1}')
echo "SHA256 Hash:      $WALLPAPER_SHA"
echo ""

# Find .hdf files to update
HDF_FILES=()
if [ -n "$HDF_TARGET" ]; then
    if [ -f "$HDF_TARGET" ]; then
        HDF_FILES+=("$HDF_TARGET")
    else
        echo "❌ Error: Specified directives file '$HDF_TARGET' not found."
        exit 1
    fi
else
    # Auto-discover all .hdf files in directory
    while IFS= read -r -d $'\0' file; do
        HDF_FILES+=("$file")
    done < <(find "$SCRIPT_DIR" -maxdepth 2 -name "*.hdf" -print0)
fi

if [ ${#HDF_FILES[@]} -eq 0 ]; then
    echo "⚠️ No .hdf directives files found in $SCRIPT_DIR."
    echo "   SHA256 is: $WALLPAPER_SHA"
else
    echo "Found ${#HDF_FILES[@]} directives file(s) to update:"
    for hdf in "${HDF_FILES[@]}"; do
        echo "  - $hdf"
        # Update or add WallpaperSha256 in the .hdf file
        if grep -q "^WallpaperSha256=" "$hdf"; then
            sed -i "s|^WallpaperSha256=.*|WallpaperSha256=$WALLPAPER_SHA|g" "$hdf"
        fi
    done
    echo ""
    echo "✓ Directives file(s) updated successfully with SHA256:"
    echo "  $WALLPAPER_SHA"
fi

echo "============================================="
