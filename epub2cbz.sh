#!/usr/bin/env bash
# convert.sh - Batch convert all .epub files in a directory to .cbz
# Usage: ./convert.sh [source_dir] [output_dir]
# Defaults: source_dir=current dir, output_dir=<source_dir>/cbz
#
# Depends on: Python 3, epub2cbz.py (must be in same directory as this script)

set -euo pipefail

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
header()  { echo -e "\n${BOLD}$*${RESET}"; }

# ── Resolve script location so we can find epub2cbz.py ────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_SCRIPT="${SCRIPT_DIR}/epub2cbz.py"

# ── Argument handling ─────────────────────────────────────────────────────────
INPUT="${1:-.}"
INPUT="$(realpath "$INPUT")"   # Absolute path, resolves ~ and symlinks

# ── Pre-flight checks ─────────────────────────────────────────────────────────
header "EPUB → CBZ Converter"

# Check Python
if ! command -v python3 &>/dev/null; then
    error "python3 not found. Please install Python 3."
    exit 1
fi

PYTHON_VERSION="$(python3 --version 2>&1)"
info "Using $PYTHON_VERSION"

# Check converter script
if [[ ! -f "$PYTHON_SCRIPT" ]]; then
    error "epub2cbz.py not found at: $PYTHON_SCRIPT"
    error "Make sure epub2cbz.py is in the same directory as convert.sh"
    exit 1
fi

# ── Collect EPUB files depending on whether input is a file or directory ──────
if [[ -f "$INPUT" ]]; then
    # Single file mode
    if [[ "${INPUT##*.}" != "epub" ]]; then
        error "File is not an .epub: $INPUT"
        exit 1
    fi
    EPUB_FILES=("$INPUT")
    SOURCE_DIR="$(dirname "$INPUT")"
    OUTPUT_DIR="${2:-${SOURCE_DIR}/cbz}"
    info "Mode    : single file"

elif [[ -d "$INPUT" ]]; then
    # Directory mode
    SOURCE_DIR="$INPUT"
    OUTPUT_DIR="${2:-${SOURCE_DIR}/cbz}"
    mapfile -t EPUB_FILES < <(find "$SOURCE_DIR" -maxdepth 1 -name "*.epub" | sort)
    info "Mode    : directory"

else
    error "Input not found: $INPUT"
    error "Usage: $0 <file.epub|directory> [output_dir]"
    exit 1
fi

echo -e "  Source : ${CYAN}${INPUT}${RESET}"
echo -e "  Output : ${CYAN}${OUTPUT_DIR}${RESET}"
echo

TOTAL=${#EPUB_FILES[@]}

if [[ $TOTAL -eq 0 ]]; then
    warn "No .epub files found in: $SOURCE_DIR"
    exit 0
fi

info "Found ${BOLD}${TOTAL}${RESET} EPUB file(s) to convert."

# ── Create output directory ───────────────────────────────────────────────────
mkdir -p "$OUTPUT_DIR"

# ── Convert loop ──────────────────────────────────────────────────────────────
PASS=0
FAIL=0
SKIP=0
FAILED_FILES=()

for epub in "${EPUB_FILES[@]}"; do
    BASENAME="$(basename "$epub")"
    STEM="${BASENAME%.epub}"
    CBZ="${OUTPUT_DIR}/${STEM}.cbz"

    # Skip if CBZ already exists and is newer than the source EPUB
    if [[ -f "$CBZ" && "$CBZ" -nt "$epub" ]]; then
        warn "Skipping (up to date): $BASENAME"
        (( SKIP++ )) || true
        continue
    fi

    echo -ne "  Converting: ${CYAN}${BASENAME}${RESET} ... "

    # Run Python converter; capture stderr separately
    if python3 "$PYTHON_SCRIPT" "$epub" "$CBZ" 2>/tmp/epub_cbz_err; then
        echo -e "${GREEN}done${RESET}"
        (( PASS++ )) || true
    else
        echo -e "${RED}FAILED${RESET}"
        # Print captured stderr indented for readability
        while IFS= read -r line; do
            echo -e "    ${RED}${line}${RESET}"
        done < /tmp/epub_cbz_err
        FAILED_FILES+=("$BASENAME")
        (( FAIL++ )) || true
    fi
done

# ── Summary ───────────────────────────────────────────────────────────────────
header "Summary"
echo -e "  Total   : ${BOLD}${TOTAL}${RESET}"
echo -e "  ${GREEN}Converted${RESET}: ${PASS}"
[[ $SKIP -gt 0 ]] && echo -e "  ${YELLOW}Skipped${RESET}  : ${SKIP} (already up to date)"
[[ $FAIL -gt 0 ]] && echo -e "  ${RED}Failed${RESET}   : ${FAIL}"

if [[ ${#FAILED_FILES[@]} -gt 0 ]]; then
    echo
    error "The following files could not be converted:"
    for f in "${FAILED_FILES[@]}"; do
        echo -e "    ${RED}✗${RESET} $f"
    done
    exit 1
fi

echo
success "All conversions complete. CBZ files are in: ${OUTPUT_DIR}"
exit 0
