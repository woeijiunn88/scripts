#!/bin/bash
# usb-mount.sh — Mount and unmount USB drives (CLI, SSH-friendly)
# Mounts under /mnt/usb/<label> owned by woeijiunn88 (uid/gid 1000)
# Usage: usb-mount [mount|unmount]
#
# One-time sudoers setup (run once as root):
#   echo 'woeijiunn88 ALL=(root) NOPASSWD: /usr/bin/mount, /usr/bin/umount, /bin/mkdir, /usr/bin/chown, /usr/bin/rmdir, /usr/bin/fuser' \
#     > /etc/sudoers.d/usb-mount
#   chmod 440 /etc/sudoers.d/usb-mount

MOUNT_BASE="/mnt/usb"
MOUNT_USER="$(whoami)"
MOUNT_UID=$(id -u)
MOUNT_GID=$(id -g)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ─── Helper: get USB devices ─────────────────────────────────────────────────

get_usb_devs() {
    local -n _OUT=$1
    _OUT=()
    mapfile -t USB_PARENTS < <(lsblk -dpno NAME,TRAN | awk '$2=="usb" {print $1}')
    for DEV in "${USB_PARENTS[@]}"; do
        PARTS=$(lsblk -lnpo NAME "$DEV" | tail -n +2)
        if [[ -n "$PARTS" ]]; then
            while IFS= read -r PART; do
                _OUT+=("$PART")
            done <<< "$PARTS"
        else
            _OUT+=("$DEV")
        fi
    done
}

# ─── Helper: parse selection string into array of indices ────────────────────
# Accepts: "1 2 3" or "1,2,3" or "1, 2, 3"

parse_selection() {
    local INPUT="$1"
    local MAX="$2"
    local -n _RESULT=$3
    _RESULT=()

    # Normalize separators
    INPUT=$(echo "$INPUT" | tr ',' ' ')

    for TOKEN in $INPUT; do
        if ! [[ "$TOKEN" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}Invalid selection: '$TOKEN' is not a number.${RESET}"
            return 1
        fi
        if (( TOKEN < 1 || TOKEN > MAX )); then
            echo -e "${RED}Invalid selection: $TOKEN is out of range (1-$MAX).${RESET}"
            return 1
        fi
        _RESULT+=("$TOKEN")
    done

    if [[ ${#_RESULT[@]} -eq 0 ]]; then
        echo -e "${RED}No valid selections made.${RESET}"
        return 1
    fi
    return 0
}

# ─── Helper: print device table ──────────────────────────────────────────────

print_table() {
    local -n _DEVS=$1
    printf "  %-4s %-12s %-10s %-8s %-20s %s\n" "No." "Device" "FSType" "Size" "Label" "Mount Point"
    printf "  %-4s %-12s %-10s %-8s %-20s %s\n" "---" "------" "------" "----" "-----" "-----------"
    local INDEX=1
    for DEV in "${_DEVS[@]}"; do
        FSTYPE=$(lsblk -no FSTYPE    "$DEV" 2>/dev/null | head -1)
        SIZE=$(lsblk -no SIZE        "$DEV" 2>/dev/null | head -1)
        LABEL=$(lsblk -no LABEL      "$DEV" 2>/dev/null | head -1)
        MOUNT=$(lsblk -no MOUNTPOINT "$DEV" 2>/dev/null | head -1)
        [[ -z "$FSTYPE" ]] && FSTYPE="-"
        [[ -z "$LABEL"  ]] && LABEL="-"
        if [[ -n "$MOUNT" ]]; then
            MOUNT_DISPLAY="${GREEN}${MOUNT}${RESET}"
        else
            MOUNT_DISPLAY="${YELLOW}not mounted${RESET}"
        fi
        printf "  ${BOLD}%-4s${RESET} %-12s %-10s %-8s %-20s " \
            "$INDEX" "$DEV" "$FSTYPE" "$SIZE" "$LABEL"
        echo -e "$MOUNT_DISPLAY"
        ((INDEX++))
    done
}

# ─── Helper: mount a single device ───────────────────────────────────────────

mount_one() {
    local DEV="$1"
    local FSTYPE LABEL MOUNT SAFE_LABEL DEFAULT_MOUNT MOUNT_POINT

    FSTYPE=$(lsblk -no FSTYPE    "$DEV" 2>/dev/null | head -1)
    LABEL=$(lsblk -no LABEL      "$DEV" 2>/dev/null | head -1)
    MOUNT=$(lsblk -no MOUNTPOINT "$DEV" 2>/dev/null | head -1)

    if [[ -n "$MOUNT" ]]; then
        echo -e "${YELLOW}  $DEV is already mounted at $MOUNT — skipping.${RESET}"
        return
    fi

    SAFE_LABEL=$(echo "$LABEL" | tr ' ' '_' | tr -cd '[:alnum:]_-')
    [[ -z "$SAFE_LABEL" ]] && SAFE_LABEL=$(basename "$DEV")
    DEFAULT_MOUNT="$MOUNT_BASE/$SAFE_LABEL"

    read -rp "  Mount point for $DEV [$DEFAULT_MOUNT]: " MOUNT_POINT
    [[ -z "$MOUNT_POINT" ]] && MOUNT_POINT="$DEFAULT_MOUNT"

    if [[ ! -d "$MOUNT_POINT" ]]; then
        sudo mkdir -p "$MOUNT_POINT"
        sudo chown $MOUNT_UID:$MOUNT_GID "$MOUNT_POINT"
    fi

    echo -e "  Mounting ${CYAN}$DEV${RESET} ($FSTYPE) -> ${CYAN}$MOUNT_POINT${RESET} as ${CYAN}$MOUNT_USER${RESET} ..."

    case "$FSTYPE" in
        vfat|fat|fat16|fat32|exfat|ntfs|ntfs3|ntfs-3g|fuseblk)
            sudo mount -o uid=$MOUNT_UID,gid=$MOUNT_GID,fmask=0022,dmask=0022 "$DEV" "$MOUNT_POINT"
            ;;
        ext2|ext3|ext4|btrfs|xfs|f2fs)
            sudo mount "$DEV" "$MOUNT_POINT"
            sudo chown $MOUNT_UID:$MOUNT_GID "$MOUNT_POINT"
            ;;
        *)
            sudo mount "$DEV" "$MOUNT_POINT"
            sudo chown $MOUNT_UID:$MOUNT_GID "$MOUNT_POINT" 2>/dev/null
            ;;
    esac

    if mountpoint -q "$MOUNT_POINT"; then
        echo -e "  ${GREEN}Mounted successfully at $MOUNT_POINT (owner: $MOUNT_USER [$MOUNT_UID:$MOUNT_GID])${RESET}"
    else
        echo -e "  ${RED}Mount failed. Check: dmesg | tail -20${RESET}"
    fi
}

# ─── Helper: unmount a single device ─────────────────────────────────────────

unmount_one() {
    local DEV="$1"
    local MOUNT="$2"

    while true; do
        echo -e "  Unmounting ${CYAN}$DEV${RESET} from ${CYAN}$MOUNT${RESET} ..."
        sudo umount "$DEV" 2>/dev/null

        if ! mountpoint -q "$MOUNT" 2>/dev/null; then
            echo -e "  ${GREEN}Unmounted successfully.${RESET}"
            if [[ "$MOUNT" == "$MOUNT_BASE/"* ]]; then
                if sudo rmdir "$MOUNT" 2>/dev/null; then
                    echo -e "  ${GREEN}Mount directory removed: $MOUNT${RESET}"
                else
                    echo -e "  ${YELLOW}Warning: could not remove $MOUNT (non-empty or permission error).${RESET}"
                fi
            fi
            return
        fi

        # Unmount failed — show busy processes
        echo -e "  ${RED}Failed to unmount $DEV. Device is busy.${RESET}\n"
        echo -e "  ${BOLD}Processes using $MOUNT:${RESET}"
        echo -e "  ────────────────────────────────────────"
        LSOF_OUT=$(lsof +D "$MOUNT" 2>/dev/null)
        if [[ -n "$LSOF_OUT" ]]; then
            printf "  %-8s %-12s %-10s %-6s %s\n" "PID" "USER" "FD" "TYPE" "COMMAND"
            printf "  %-8s %-12s %-10s %-6s %s\n" "---" "----" "--" "----" "-------"
            echo "$LSOF_OUT" | awk 'NR>1 {printf "  %-8s %-12s %-10s %-6s %s\n", $2, $3, $4, $5, $1}'
        else
            FUSER_OUT=$(fuser -mv "$MOUNT" 2>&1 | tail -n +2)
            if [[ -n "$FUSER_OUT" ]]; then
                printf "  %-8s %-12s %-6s %s\n" "PID" "USER" "ACCESS" "COMMAND"
                printf "  %-8s %-12s %-6s %s\n" "---" "----" "------" "-------"
                echo "$FUSER_OUT" | while read -r F_USER F_PID F_ACCESS F_CMD; do
                    printf "  %-8s %-12s %-6s %s\n" "$F_PID" "$F_USER" "$F_ACCESS" "$F_CMD"
                done
            else
                echo -e "  ${YELLOW}Could not identify processes.${RESET}"
            fi
        fi
        echo -e "  ────────────────────────────────────────\n"

        # Retry / Force / Abort
        echo -e "  ${BOLD}Options:${RESET}"
        echo "    r) Retry unmount"
        echo "    f) Force unmount (kills all processes)"
        echo "    a) Abort"
        echo ""
        read -rp "  Choose [r/f/a]: " ACTION
        case "${ACTION,,}" in
            r)
                echo -e "  ${YELLOW}Retrying...${RESET}"
                continue
                ;;
            f)
                echo -e "  Killing processes using ${CYAN}$MOUNT${RESET} ..."
                sudo fuser -km "$MOUNT" 2>/dev/null
                sleep 1
                echo -e "  Lazy force unmounting ${CYAN}$DEV${RESET} ..."
                sudo umount -l "$DEV" 2>/dev/null
                if ! mountpoint -q "$MOUNT" 2>/dev/null; then
                    echo -e "  ${GREEN}Force unmounted successfully.${RESET}"
                    if [[ "$MOUNT" == "$MOUNT_BASE/"* ]]; then
                        if sudo rmdir "$MOUNT" 2>/dev/null; then
                            echo -e "  ${GREEN}Mount directory removed: $MOUNT${RESET}"
                        else
                            echo -e "  ${YELLOW}Warning: could not remove $MOUNT (non-empty or permission error).${RESET}"
                        fi
                    fi
                else
                    echo -e "  ${RED}Force unmount failed. Try manually: sudo umount -f $DEV${RESET}"
                fi
                return
                ;;
            a)
                echo -e "  ${YELLOW}Aborted unmount of $DEV.${RESET}"
                return
                ;;
            *)
                echo -e "  ${RED}Invalid option.${RESET}"
                ;;
        esac
    done
}

# ─── do_mount ────────────────────────────────────────────────────────────────

do_mount() {
    get_usb_devs ALL_DEVS

    if [[ ${#ALL_DEVS[@]} -eq 0 ]]; then
        echo -e "${RED}No USB devices detected.${RESET}"
        exit 1
    fi

    echo -e "\n${BOLD}${CYAN}=== USB Devices ===${RESET}\n"
    print_table ALL_DEVS
    echo ""
    read -rp "Select device(s) to mount (e.g. 1 2 3 or 1,2,3 | a = all | q = quit): " CHOICE
    [[ "$CHOICE" == "q" || -z "$CHOICE" ]] && exit 0

    SELECTED=()
    if [[ "$CHOICE" == "a" ]]; then
        for i in "${!ALL_DEVS[@]}"; do SELECTED+=("$((i+1))"); done
    else
        parse_selection "$CHOICE" "${#ALL_DEVS[@]}" SELECTED || exit 1
    fi

    echo ""
    for IDX in "${SELECTED[@]}"; do
        mount_one "${ALL_DEVS[$((IDX-1))]}"
        echo ""
    done
}

# ─── do_unmount ──────────────────────────────────────────────────────────────

do_unmount() {
    get_usb_devs ALL_DEVS

    MOUNTED_DEVS=()
    MOUNTED_POINTS=()
    for DEV in "${ALL_DEVS[@]}"; do
        MOUNT=$(lsblk -no MOUNTPOINT "$DEV" 2>/dev/null | head -1)
        if [[ -n "$MOUNT" ]]; then
            MOUNTED_DEVS+=("$DEV")
            MOUNTED_POINTS+=("$MOUNT")
        fi
    done

    if [[ ${#MOUNTED_DEVS[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No mounted USB devices found.${RESET}"
        exit 0
    fi

    echo -e "\n${BOLD}${CYAN}=== Mounted USB Devices ===${RESET}\n"
    printf "  %-4s %-12s %-10s %-8s %-20s %s\n" "No." "Device" "FSType" "Size" "Label" "Mount Point"
    printf "  %-4s %-12s %-10s %-8s %-20s %s\n" "---" "------" "------" "----" "-----" "-----------"
    for i in "${!MOUNTED_DEVS[@]}"; do
        DEV="${MOUNTED_DEVS[$i]}"
        MOUNT="${MOUNTED_POINTS[$i]}"
        FSTYPE=$(lsblk -no FSTYPE "$DEV" 2>/dev/null | head -1)
        SIZE=$(lsblk -no SIZE     "$DEV" 2>/dev/null | head -1)
        LABEL=$(lsblk -no LABEL   "$DEV" 2>/dev/null | head -1)
        [[ -z "$FSTYPE" ]] && FSTYPE="-"
        [[ -z "$LABEL"  ]] && LABEL="-"
        printf "  ${BOLD}%-4s${RESET} %-12s %-10s %-8s %-20s " \
            "$((i+1))" "$DEV" "$FSTYPE" "$SIZE" "$LABEL"
        echo -e "${GREEN}$MOUNT${RESET}"
    done

    echo ""
    read -rp "Select device(s) to unmount (e.g. 1 2 3 or 1,2,3 | a = all | q = quit): " CHOICE
    [[ "$CHOICE" == "q" || -z "$CHOICE" ]] && exit 0

    SELECTED=()
    if [[ "$CHOICE" == "a" ]]; then
        for i in "${!MOUNTED_DEVS[@]}"; do SELECTED+=("$((i+1))"); done
    else
        parse_selection "$CHOICE" "${#MOUNTED_DEVS[@]}" SELECTED || exit 1
    fi

    echo ""
    for IDX in "${SELECTED[@]}"; do
        unmount_one "${MOUNTED_DEVS[$((IDX-1))]}" "${MOUNTED_POINTS[$((IDX-1))]}"
        echo ""
    done
}

# ─── Main menu ───────────────────────────────────────────────────────────────

case "${1,,}" in
    mount)   do_mount   ;;
    unmount) do_unmount ;;
    *)
        echo -e "\n${BOLD}USB Mount Manager${RESET} (user: $MOUNT_USER [$MOUNT_UID:$MOUNT_GID])"
        echo "  1) Mount USB"
        echo "  2) Unmount USB"
        echo ""
        read -rp "Choose [1/2] (or q to quit): " OPT
        case "$OPT" in
            1) do_mount   ;;
            2) do_unmount ;;
            *) exit 0     ;;
        esac
        ;;
esac