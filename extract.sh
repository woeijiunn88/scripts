#!/usr/bin/env bash
# =============================================================================
# extract.sh — Universal Archive Extractor
# =============================================================================
#
# Supported formats:
#   .rar                — unrar
#   .zip                — unzip
#   .7z                 — 7z
#   .tar                — tar
#   .tar.gz / .tgz      — tar
#   .tar.bz2 / .tbz2    — tar
#   .tar.xz / .txz      — tar
#   .tar.zst            — tar
#   .gz                 — gunzip  (single file, not a tar)
#   .bz2                — bunzip2 (single file, not a tar)
#   .xz                 — xz      (single file, not a tar)
#
# Output path:
#   Default: extract into a subfolder named after the archive, inside the
#            archive's own directory  (e.g. /music/Album.rar → /music/Album/)
#   Custom : prompted if you answer y to "Set output path?"
#
# Windows path support:
#   F:\ → /mnt/sda1     G:\ → /mnt/sdb1
#   H:\ → /mnt/sdc1     Z:\ → $HOME
#
# Requirements (install only what you need):
#   unrar  — sudo apt install unrar
#   unzip  — sudo apt install unzip
#   7zip   — sudo apt install 7zip        (provides 7z)
#   tar    — pre-installed on most systems
#   xz     — sudo apt install xz-utils
#
# Usage:
#   ./extract.sh
# =============================================================================

# ─── ANSI colour palette ──────────────────────────────────────────────────────
RED='\033[0;31m';     YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m';    MAGENTA='\033[0;35m'; BOLD='\033[1m'; RESET='\033[0m'
DIM='\033[2m'

# ─── Logging helpers ──────────────────────────────────────────────────────────
log()       { echo -e "${CYAN}[INFO]${RESET}    $*"; }
log_ok()    { echo -e "${GREEN}[OK]${RESET}      $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${RESET}    $*"; }
log_err()   { echo -e "${RED}[ERROR]${RESET}   $*" >&2; }
log_step()  { echo -e "\n${BOLD}${MAGENTA}▶  $*${RESET}"; }
log_skip()  { echo -e "${DIM}[SKIP]    $*${RESET}"; }
die()       { log_err "$*"; exit 1; }

# =============================================================================
# Windows path translation
# =============================================================================
translate_windows_path() {
    local input="$1"

    if [[ "$input" =~ ^([A-Za-z]):[/\\] ]]; then
        local drive_letter="${BASH_REMATCH[1]}"
        local mount_point

        case "${drive_letter^^}" in
            F) mount_point="/mnt/sda1" ;;
            G) mount_point="/mnt/sdb1" ;;
            H) mount_point="/mnt/sdc1" ;;
            Z) mount_point="$HOME"     ;;
            *)
                echo -e "\n${RED}[ERROR]${RESET} Unsupported Windows drive: ${BOLD}${drive_letter}:\\${RESET}" >&2
                echo -e "         Supported:  ${BOLD}F:\\${RESET} /mnt/sda1  ${BOLD}G:\\${RESET} /mnt/sdb1  ${BOLD}H:\\${RESET} /mnt/sdc1  ${BOLD}Z:\\${RESET} ${HOME}" >&2
                return 1
                ;;
        esac

        local remainder="${input:3}"
        remainder="${remainder//\\//}"
        remainder="${remainder%/}"

        if [[ -n "$remainder" ]]; then
            echo "${mount_point}/${remainder}"
        else
            echo "${mount_point}"
        fi
        return 0
    fi

    echo "$input"
    return 0
}

# =============================================================================
# Prompt helpers
# =============================================================================

# Resolve and validate a path input (file or directory).
# $1 = prompt label, $2 = nameref for result, $3 = "file" or "dir"
prompt_path() {
    local label="$1"
    local -n _path_result=$2
    local expect="$3"   # "file" or "dir"

    while true; do
        read -rp "$(printf "  ${BOLD}%s${RESET} > " "$label")" raw </dev/tty
        raw="${raw#[\'\"]}"
        raw="${raw%[\'\"]}"
        raw="${raw/#\~/$HOME}"

        [[ -z "$raw" ]] && { log_warn "Path cannot be empty."; continue; }

        local translated
        translated="$(translate_windows_path "$raw")" || continue

        local resolved
        resolved="$(realpath "$translated" 2>/dev/null)" || resolved="$translated"

        if [[ "$expect" == "file" && ! -f "$resolved" ]]; then
            log_warn "File not found: ${BOLD}$resolved${RESET}"
            continue
        fi
        if [[ "$expect" == "dir" && ! -d "$resolved" ]]; then
            mkdir -p "$resolved" 2>/dev/null \
                || { log_warn "Cannot create directory: ${BOLD}$resolved${RESET}"; continue; }
            log_ok "Created: ${BOLD}$resolved${RESET}"
        fi

        _path_result="$resolved"
        break
    done
}

# Single-shot yes/no — Enter defaults to no
prompt_yes_no() {
    local question="$1"
    local answer
    read -rp "$(printf "  ${BOLD}%s${RESET} [y/Enter=no]: " "$question")" answer </dev/tty
    case "${answer,,}" in
        y|yes) return 0 ;;
        *)     return 1 ;;
    esac
}

# =============================================================================
# Detect archive type from filename
# Returns a short type string, or empty string if unrecognised.
# =============================================================================
detect_type() {
    local file="$1"
    local lower="${file,,}"

    case "$lower" in
        *.tar.gz|*.tgz)       echo "tar.gz"  ;;
        *.tar.bz2|*.tbz2)     echo "tar.bz2" ;;
        *.tar.xz|*.txz)       echo "tar.xz"  ;;
        *.tar.zst)             echo "tar.zst" ;;
        *.tar)                 echo "tar"     ;;
        *.rar)                 echo "rar"     ;;
        *.zip)                 echo "zip"     ;;
        *.7z)                  echo "7z"      ;;
        *.gz)                  echo "gz"      ;;
        *.bz2)                 echo "bz2"     ;;
        *.xz)                  echo "xz"      ;;
        *)                     echo ""        ;;
    esac
}

# =============================================================================
# Check that the required tool for a given type is installed
# =============================================================================
check_tool_for_type() {
    local type="$1"
    local tool

    case "$type" in
        rar)                         tool="unrar" ;;
        zip)                         tool="unzip" ;;
        7z)                          tool="7z"    ;;
        tar|tar.gz|tar.bz2|tar.xz|tar.zst) tool="tar" ;;
        gz)                          tool="gunzip"  ;;
        bz2)                         tool="bunzip2" ;;
        xz)                          tool="xz"      ;;
    esac

    if ! command -v "$tool" &>/dev/null; then
        case "$tool" in
            unrar)   die "'unrar' not found. Install: sudo apt install unrar" ;;
            unzip)   die "'unzip' not found. Install: sudo apt install unzip" ;;
            7z)      die "'7z' not found. Install: sudo apt install 7zip" ;;
            tar)     die "'tar' not found. Install: sudo apt install tar" ;;
            gunzip)  die "'gunzip' not found. Install: sudo apt install gzip" ;;
            bunzip2) die "'bunzip2' not found. Install: sudo apt install bzip2" ;;
            xz)      die "'xz' not found. Install: sudo apt install xz-utils" ;;
        esac
    fi
}

# =============================================================================
# Run the appropriate extraction command
# =============================================================================
run_extract() {
    local archive="$1"
    local out_dir="$2"
    local type="$3"

    mkdir -p "$out_dir" || die "Cannot create output directory: $out_dir"

    case "$type" in
        rar)
            unrar x "$archive" "$out_dir/"
            ;;
        zip)
            unzip -q "$archive" -d "$out_dir"
            ;;
        7z)
            7z x "$archive" -o"$out_dir" -y
            ;;
        tar)
            tar -xf "$archive" -C "$out_dir"
            ;;
        tar.gz)
            tar -xzf "$archive" -C "$out_dir"
            ;;
        tar.bz2)
            tar -xjf "$archive" -C "$out_dir"
            ;;
        tar.xz)
            tar -xJf "$archive" -C "$out_dir"
            ;;
        tar.zst)
            tar --zstd -xf "$archive" -C "$out_dir"
            ;;
        gz)
            # Single .gz file — decompress in-place to out_dir
            local base_name
            base_name="$(basename "${archive%.gz}")"
            gunzip -c "$archive" > "${out_dir}/${base_name}"
            ;;
        bz2)
            local base_name
            base_name="$(basename "${archive%.bz2}")"
            bunzip2 -c "$archive" > "${out_dir}/${base_name}"
            ;;
        xz)
            local base_name
            base_name="$(basename "${archive%.xz}")"
            xz -d -c "$archive" > "${out_dir}/${base_name}"
            ;;
        *)
            die "Unknown archive type: $type"
            ;;
    esac
}

# =============================================================================
# Strip known archive extensions to get a clean base name for the output folder
# =============================================================================
archive_basename() {
    local file="$1"
    local name
    name="$(basename "$file")"

    # Strip compound extensions first
    case "${name,,}" in
        *.tar.gz)  name="${name%.*}"; name="${name%.*}" ;;
        *.tar.bz2) name="${name%.*}"; name="${name%.*}" ;;
        *.tar.xz)  name="${name%.*}"; name="${name%.*}" ;;
        *.tar.zst) name="${name%.*}"; name="${name%.*}" ;;
        *.tgz|*.tbz2|*.txz)
                   name="${name%.*}" ;;
        *)         name="${name%.*}" ;;
    esac

    echo "$name"
}

# =============================================================================
# Extract a single archive file
# =============================================================================
extract_one() {
    local archive="$1"
    local out_dir="$2"
    local type
    type="$(detect_type "$archive")"

    if [[ -z "$type" ]]; then
        log_warn "Unrecognised format, skipping: ${BOLD}$(basename "$archive")${RESET}"
        return 1
    fi

    check_tool_for_type "$type"

    log      "Archive : ${BOLD}$(basename "$archive")${RESET}"
    log      "Type    : ${CYAN}${type}${RESET}"
    log      "Output  : ${BOLD}$out_dir${RESET}"
    echo ""

    if run_extract "$archive" "$out_dir" "$type"; then
        echo ""
        log_ok "Extracted: ${BOLD}$out_dir${RESET}"
        return 0
    else
        log_err "Extraction failed: $(basename "$archive")"
        return 1
    fi
}

# =============================================================================
# Collect all archives in a directory (non-recursive)
# =============================================================================
find_archives_in_dir() {
    local dir="$1"
    local -n _found=$2

    _found=()
    while IFS= read -r -d '' f; do
        local t
        t="$(detect_type "$f")"
        [[ -n "$t" ]] && _found+=( "$f" )
    done < <(find "$dir" -mindepth 1 -maxdepth 1 -type f -print0 | sort -z)
}

# =============================================================================
# Main
# =============================================================================
main() {
    echo ""
    echo -e "${BOLD}${CYAN}══════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}${CYAN}   extract.sh  —  Universal Archive Extractor  ${RESET}"
    echo -e "${BOLD}${CYAN}   rar · zip · 7z · tar · tar.xz · tar.gz     ${RESET}"
    echo -e "${BOLD}${CYAN}══════════════════════════════════════════════${RESET}"
    echo ""

    # ── Step 1: Source — file or directory? ───────────────────────────────────
    log_step "Archive source"
    printf '  \033[2mWindows paths accepted (e.g. G:\\Downloads\\Album.rar)\033[0m\n'
    echo -e "  ${DIM}Enter a single archive file, or a directory to batch-extract all archives inside it${RESET}"
    echo ""

    local src_path
    prompt_path "Archive file or directory" src_path "any"

    # Resolve "any" — re-validate as file or dir
    if [[ ! -f "$src_path" && ! -d "$src_path" ]]; then
        die "Path does not exist: $src_path"
    fi

    # ── Step 2: Output path ───────────────────────────────────────────────────
    log_step "Output path"
    echo -e "  ${DIM}Default: each archive extracts into a subfolder beside itself${RESET}"
    echo ""

    local custom_out_dir=""
    if prompt_yes_no "Set a custom output path?"; then
        echo -e "  ${DIM}Windows paths accepted${RESET}"
        prompt_path "Output directory" custom_out_dir "dir"
        log_ok "Output : $custom_out_dir"
    else
        log "Output : ${DIM}default — subfolder beside each archive${RESET}"
    fi

    # ── Step 3: Collect archives ──────────────────────────────────────────────
    local -a archives=()

    if [[ -f "$src_path" ]]; then
        archives=( "$src_path" )
    else
        log_step "Scanning directory"
        log "Directory: ${BOLD}$src_path${RESET}"
        find_archives_in_dir "$src_path" archives

        if [[ ${#archives[@]} -eq 0 ]]; then
            die "No supported archives found in: $src_path"
        fi

        log_ok "Found ${BOLD}${#archives[@]}${RESET} archive(s):"
        for a in "${archives[@]}"; do
            echo -e "    ${DIM}$(basename "$a")${RESET}"
        done
    fi

    # ── Step 4: Extract ───────────────────────────────────────────────────────
    local total="${#archives[@]}"
    local succeeded=0 failed=0
    local idx=0

    for archive in "${archives[@]}"; do
        idx=$(( idx + 1 ))
        echo ""
        echo -e "${BOLD}${MAGENTA}▶  [${idx}/${total}] $(basename "$archive")${RESET}"

        # Determine output directory for this archive
        local out_dir
        if [[ -n "$custom_out_dir" ]]; then
            # Custom path: if multiple archives, put each in its own subfolder
            if [[ $total -gt 1 ]]; then
                local base
                base="$(archive_basename "$archive")"
                out_dir="${custom_out_dir}/${base}"
            else
                out_dir="$custom_out_dir"
            fi
        else
            # Default: subfolder beside the archive
            local archive_dir base
            archive_dir="$(dirname "$archive")"
            base="$(archive_basename "$archive")"
            out_dir="${archive_dir}/${base}"
        fi

        if extract_one "$archive" "$out_dir"; then
            succeeded=$(( succeeded + 1 ))
        else
            failed=$(( failed + 1 ))
        fi
    done

    # ── Summary ───────────────────────────────────────────────────────────────
    echo ""
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${GREEN}║        Extraction complete  ✓                ║${RESET}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "  ${BOLD}Total   :${RESET} $total"
    echo -e "  ${BOLD}Success :${RESET} ${GREEN}${succeeded}${RESET}"
    [[ $failed -gt 0 ]] && \
    echo -e "  ${BOLD}Failed  :${RESET} ${RED}${failed}${RESET}"
    echo ""

    [[ $failed -gt 0 ]] && exit 1
    exit 0
}

main "$@"