#!/usr/bin/env bash
# =============================================================================
# rar_rr5.sh — RAR Archiver with 5% Recovery Record
# =============================================================================
#
# Modes:
#   1. Single archive  — packs the entire source directory into one .rar
#                        (optional: split into 2 GB parts, optional password)
#   2. Per-subfolder   — creates one .rar per immediate sub-directory found
#                        inside the source directory
#
# Windows path support:
#   F:\ → /mnt/sda1     G:\ → /mnt/sdb1
#   H:\ → /mnt/sdc1     Z:\ → $HOME
#
# Requirements:
#   rar   — RAR archiver (install: sudo apt install rar)
#
# Usage:
#   ./rar_rr5.sh
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
# Translates Windows drive paths (e.g. G:\Music\Album) to Linux mount points.
# Supported mappings:
#   F:\ → /mnt/sda1    G:\ → /mnt/sdb1
#   H:\ → /mnt/sdc1    Z:\ → $HOME
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

        # Strip drive prefix and convert backslashes
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

    # Not a Windows path — return as-is
    echo "$input"
    return 0
}

# =============================================================================
# Prompt helpers
# =============================================================================

# Prompt for a directory path (must exist), with Windows path support.
# Sets the named variable to the resolved absolute path.
prompt_directory() {
    local prompt_label="$1"   # e.g. "Source directory"
    local -n _result=$2       # nameref: variable to store the result

    while true; do
        read -rp "$(printf "  ${BOLD}%s${RESET} > " "$prompt_label")" raw_input </dev/tty

        # Strip surrounding quotes (copy-paste from Explorer)
        raw_input="${raw_input#[\'\"]}"
        raw_input="${raw_input%[\'\"]}"
        # Expand leading ~
        raw_input="${raw_input/#\~/$HOME}"

        [[ -z "$raw_input" ]] && { log_warn "Path cannot be empty."; continue; }

        # Translate Windows path
        local translated
        translated="$(translate_windows_path "$raw_input")" || continue

        # Resolve to absolute path
        local resolved
        resolved="$(realpath "$translated" 2>/dev/null)" || resolved="$translated"

        if [[ ! -d "$resolved" ]]; then
            log_warn "Directory not found: ${BOLD}$resolved${RESET}"
            continue
        fi

        _result="$resolved"
        break
    done
}

# Prompt for an output directory path (created if it doesn't exist).
prompt_output_directory() {
    local -n _out_result=$1

    while true; do
        read -rp "$(printf "  ${BOLD}Output directory${RESET} > ")" raw_input </dev/tty

        raw_input="${raw_input#[\'\"]}"
        raw_input="${raw_input%[\'\"]}"
        raw_input="${raw_input/#\~/$HOME}"

        [[ -z "$raw_input" ]] && { log_warn "Path cannot be empty."; continue; }

        local translated
        translated="$(translate_windows_path "$raw_input")" || continue

        local resolved
        resolved="$(realpath "$translated" 2>/dev/null)" || resolved="$translated"

        # Create output directory if needed
        if [[ ! -d "$resolved" ]]; then
            mkdir -p "$resolved" 2>/dev/null \
                || { log_warn "Cannot create directory: ${BOLD}$resolved${RESET}"; continue; }
            log_ok "Created output directory: ${BOLD}$resolved${RESET}"
        fi

        _out_result="$resolved"
        break
    done
}

# yes/no prompt — Enter defaults to no (returns 1), y/yes returns 0
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
# Dependency check
# =============================================================================
check_deps() {
    if ! command -v rar &>/dev/null; then
        die "'rar' is not installed. Install it with: sudo apt install rar"
    fi
}

# =============================================================================
# Mode 1 — Single archive of the entire source directory
# =============================================================================
archive_single() {
    local src_dir="$1"
    local out_dir="$2"
    local dir_name
    dir_name="$(basename "$src_dir")"
    local archive_base="${out_dir}/${dir_name}.rar"

    log_step "Single archive mode"
    log "Source : ${BOLD}$src_dir${RESET}"
    log "Output : ${BOLD}$out_dir${RESET}"

    # ── Split option ──────────────────────────────────────────────────────────
    local split_flag=""
    if prompt_yes_no "Split archive into parts?"; then
        local split_size_raw split_size_kb
        while true; do
            read -rp "$(printf "  ${BOLD}Part size${RESET} (e.g. 2GB, 700MB, 4096MB) [Enter=2GB]: ")" split_size_raw </dev/tty
            [[ -z "$split_size_raw" ]] && split_size_raw="2GB"

            if [[ "$split_size_raw" =~ ^([0-9]+)[[:space:]]*(GB?|MB?)$ ]]; then
                local num="${BASH_REMATCH[1]}"
                local unit="${BASH_REMATCH[2]^^}"
                case "$unit" in
                    G|GB) split_size_kb=$(( num * 1024 * 1024 )) ;;
                    M|MB) split_size_kb=$(( num * 1024 ))         ;;
                esac
                if (( split_size_kb < 1024 )); then
                    log_warn "Part size must be at least 1 MB."
                    continue
                fi
                break
            else
                log_warn "Invalid format. Examples: 2GB  700MB  4096MB"
            fi
        done
        split_flag="-v${split_size_kb}K"
        log "Split  : ${YELLOW}enabled — ${split_size_raw^^} parts${RESET}"
    else
        log "Split  : ${DIM}disabled${RESET}"
    fi

    # ── Password option ───────────────────────────────────────────────────────
    local password_flag=""
    if prompt_yes_no "Set a password?"; then
        local pw pw2
        while true; do
            read -rsp "$(printf "  ${BOLD}Password${RESET}        : ")" pw </dev/tty; echo
            read -rsp "$(printf "  ${BOLD}Confirm password${RESET}: ")" pw2 </dev/tty; echo
            if [[ "$pw" == "$pw2" ]]; then
                password_flag="-hp${pw}"
                log "Password : ${GREEN}set${RESET}"
                break
            else
                log_warn "Passwords do not match. Try again."
            fi
        done
    else
        log "Password : ${DIM}none${RESET}"
    fi

    # ── Check for existing archive ────────────────────────────────────────────
    if [[ -f "$archive_base" || -f "${archive_base%.rar}.part1.rar" ]]; then
        log_warn "Archive already exists: ${BOLD}$archive_base${RESET}"
        prompt_yes_no "Overwrite?" || { log "Aborted."; return 0; }
        rm -f "${out_dir}/${dir_name}"*.rar
    fi

    # ── Run rar ───────────────────────────────────────────────────────────────
    echo ""
    log_step "Creating archive: ${BOLD}$(basename "$archive_base")${RESET}"

    # cd to parent so rar stores the folder itself (not bare file paths)
    local parent_dir
    parent_dir="$(dirname "$src_dir")"
    cd "$parent_dir" || die "Cannot cd into parent: $parent_dir"

    # Archive the folder by name — top-level folder is preserved inside the rar
    local rar_cmd=( rar a -mt16 -rr5% -r )
    [[ -n "$password_flag" ]] && rar_cmd+=( "$password_flag" )
    [[ -n "$split_flag"    ]] && rar_cmd+=( "$split_flag" )
    rar_cmd+=( "$archive_base" "$dir_name" )

    echo -e "  ${DIM}$ ${rar_cmd[*]}${RESET}"
    echo ""

    if "${rar_cmd[@]}"; then
        echo ""
        log_ok "Archive created: ${BOLD}$archive_base${RESET}"
    else
        die "rar failed for: $archive_base"
    fi
}

# =============================================================================
# Mode 2 — One archive per immediate sub-directory
# =============================================================================
archive_per_subfolder() {
    local src_dir="$1"
    local out_dir="$2"

    log_step "Per-subfolder archive mode"
    log "Source : ${BOLD}$src_dir${RESET}"
    log "Output : ${BOLD}$out_dir${RESET}"

    # Collect immediate sub-directories
    local -a subdirs=()
    while IFS= read -r -d '' entry; do
        subdirs+=( "$entry" )
    done < <(find "$src_dir" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

    if [[ ${#subdirs[@]} -eq 0 ]]; then
        log_warn "No sub-directories found in: ${BOLD}$src_dir${RESET}"
        return 1
    fi

    log "Found  : ${BOLD}${#subdirs[@]}${RESET} sub-director$([ ${#subdirs[@]} -eq 1 ] && echo y || echo ies)"
    echo ""

    local created=0 skipped=0 failed=0
    local total="${#subdirs[@]}"
    local idx=0

    for subdir in "${subdirs[@]}"; do
        idx=$(( idx + 1 ))
        local dir_name
        dir_name="$(basename "$subdir")"
        local archive_path="${out_dir}/${dir_name}.rar"

        echo -e "  ${DIM}[${idx}/${total}]${RESET} ${BOLD}${dir_name}${RESET}"

        if [[ -f "$archive_path" ]]; then
            log_skip "Already exists — ${DIM}${archive_path}${RESET}"
            skipped=$(( skipped + 1 ))
            continue
        fi

        # Enter the *parent* directory so rar stores relative paths cleanly
        cd "$src_dir" || die "Cannot cd into: $src_dir"

        if rar a -mt16 -rr5% "$archive_path" "$dir_name"; then
            log_ok "Created : ${BOLD}$archive_path${RESET}"
            created=$(( created + 1 ))
        else
            log_err "Failed  : $archive_path"
            failed=$(( failed + 1 ))
        fi
        echo ""
    done

    # ── Summary ───────────────────────────────────────────────────────────────
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${GREEN}║        Per-subfolder archiving done  ✓       ║${RESET}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "  ${BOLD}Created :${RESET} ${GREEN}${created}${RESET}"
    echo -e "  ${BOLD}Skipped :${RESET} ${YELLOW}${skipped}${RESET}  ${DIM}(archive already existed)${RESET}"
    echo -e "  ${BOLD}Failed  :${RESET} ${RED}${failed}${RESET}"
    echo -e "  ${BOLD}Output  :${RESET} $out_dir"
    echo ""

    [[ $failed -gt 0 ]] && return 1
    return 0
}

# =============================================================================
# Main
# =============================================================================
main() {
    echo ""
    echo -e "${BOLD}${CYAN}══════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}${CYAN}   rar_rr5  —  RAR Archiver  (rr5% / mt16)    ${RESET}"
    echo -e "${BOLD}${CYAN}══════════════════════════════════════════════${RESET}"
    echo ""

    check_deps

    # ── Step 1: Path inputs ───────────────────────────────────────────────────
    log_step "Source directory"
    echo -e "  ${DIM}Windows paths accepted (e.g. G:\\Music\\Albums)${RESET}"
    local src_dir
    prompt_directory "Source directory" src_dir
    log_ok "Source : $src_dir"

    log_step "Output directory"
    echo -e "  ${DIM}Will be created if it does not exist${RESET}"
    local out_dir
    prompt_output_directory out_dir
    log_ok "Output : $out_dir"

    # ── Step 2: Mode selection ────────────────────────────────────────────────
    log_step "Archive mode"
    echo ""
    echo -e "  ${BOLD}1)${RESET} ${GREEN}Single archive${RESET}    — pack entire source directory into one .rar"
    echo -e "     ${DIM}(optionally split into 2 GB parts, optional password)${RESET}"
    echo ""
    echo -e "  ${BOLD}2)${RESET} ${GREEN}Per-subfolder${RESET}     — create one .rar for each sub-directory found"
    echo -e "     ${DIM}(skips sub-directories that already have an archive)${RESET}"
    echo ""

    local mode
    while true; do
        read -rp "$(printf "  ${BOLD}Select mode${RESET} [1/2]: ")" mode </dev/tty
        case "$mode" in
            1) break ;;
            2) break ;;
            *) log_warn "Please enter 1 or 2." ;;
        esac
    done

    echo ""

    # ── Step 3: Run selected mode ─────────────────────────────────────────────
    case "$mode" in
        1) archive_single     "$src_dir" "$out_dir" ;;
        2) archive_per_subfolder "$src_dir" "$out_dir" ;;
    esac

    # ── Final summary for single archive mode ─────────────────────────────────
    if [[ "$mode" == "1" ]]; then
        echo ""
        echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════╗${RESET}"
        echo -e "${BOLD}${GREEN}║        Archiving complete  ✓                 ║${RESET}"
        echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════╝${RESET}"
        echo ""
        echo -e "  ${BOLD}Source  :${RESET} $src_dir"
        echo -e "  ${BOLD}Output  :${RESET} $out_dir"
        echo ""
    fi
}

main "$@"