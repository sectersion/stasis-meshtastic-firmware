#!/usr/bin/env bash
set -uo pipefail

# Parse optional --board argument
TARGET_BOARD=""
for arg in "$@"; do
    case "$arg" in
        --board=*) TARGET_BOARD="${arg#*=}" ;;
        --board)   TARGET_BOARD="$2" ;;
    esac
done

# Delete .pio directory
echo "=== Deleting .pio directory ==="
rm -rf .pio

# Create dist directory
mkdir -p dist

# Extract valid PlatformIO environment names from [env:xxx] section headers
BOARD_IDS=()
while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    BOARD_IDS+=("$line")
done < <(find variants/ -name platformio.ini -exec grep -oP '(?<=\[env:)\w[\w-]*' {} \; | sort -u)

# Filter to target board if specified, otherwise take top 10
if [[ -n "$TARGET_BOARD" ]]; then
    TOP_BOARDS=("$TARGET_BOARD")
    echo "=== Building single board: $TARGET_BOARD ==="
else
    TOP_BOARDS=("${BOARD_IDS[@]:0:10}")
    echo "=== Building top 10 boards ==="
fi

TOTAL=${#TOP_BOARDS[@]}
BUILT=0
FAILED=0
CLEANED=0

# Phase 1: Build
for board in "${TOP_BOARDS[@]}"; do
    BUILT=$((BUILT + 1))
    pbar=""
    filled=$((BUILT * 20 / TOTAL))
    for ((i=0; i<filled; i++)); do pbar+="█"; done
    for ((i=filled; i<20; i++)); do pbar+="░"; done

    echo -ne "\r[${pbar}] ${BUILT}/${TOTAL} building: ${board}        "

    if pio run -e "$board" >/dev/null 2>&1; then
        # Find and copy all firmware artifacts
        for ext in uf2 hex zip ota.zip elf; do
            for f in .pio/build/"$board"/*.${ext} .pio/build/"$board"/**/*.${ext}; do
                [[ -f "$f" ]] && cp "$f" "dist/"
            done 2>/dev/null
        done
    else
        echo ""
        echo "  ⚠ Build failed for $board"
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo ""

# Phase 2: Clean
for board in "${TOP_BOARDS[@]}"; do
    CLEANED=$((CLEANED + 1))
    pbar=""
    filled=$((CLEANED * 20 / TOTAL))
    for ((i=0; i<filled; i++)); do pbar+="█"; done
    for ((i=filled; i<20; i++)); do pbar+="░"; done

    echo -ne "\r[${pbar}] ${CLEANED}/${TOTAL} cleaning:  ${board}        "
    pio run -e "$board" -t clean >/dev/null 2>&1 || true
done

echo ""
echo ""
echo "=== Done ==="
echo "Built: $((TOTAL - FAILED))/${TOTAL} succeeded, ${FAILED} failed"
echo "Firmware files in ./dist/:"
ls -1 dist/ 2>/dev/null || echo "  (none)"