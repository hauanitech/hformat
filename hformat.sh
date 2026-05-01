#!/bin/bash

set -euo pipefail

VERSION="1.0.0"
SCRIPT_NAME="hformat"
CONFIG_DIR="${HOME}/.config/hformat"
CONFIG_FILE="${CONFIG_DIR}/config"

DEFAULT_FSTYPE="fat32"
DEFAULT_LABEL=""
DEFAULT_PARTITION_TABLE="msdos"
DEFAULT_WIPE_SIGNATURES="true"
DEFAULT_AUTO_CONFIRM="false"

FSTYPE=""
LABEL=""
PARTITION_TABLE=""
WIPE_SIGNATURES=""
AUTO_CONFIRM=""

OPT_ALL=false
OPT_YES=false
OPT_DRY_RUN=false
OPT_NAME=""
OPT_TYPE=""
DEVICES=()

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

trap 'printf "\n${YELLOW}[WARN]${RESET} Interrupted. Disk may be in a partially formatted state.\n"; exit 130' INT TERM

log_info()    { printf "${CYAN}[INFO]${RESET} %s\n" "$1"; }
log_warn()    { printf "${YELLOW}[WARN]${RESET} %s\n" "$1"; }
log_error()   { printf "${RED}[ERROR]${RESET} %s\n" "$1" >&2; }
log_success() { printf "${GREEN}[OK]${RESET} %s\n" "$1"; }

die() {
    log_error "$1"
    exit "${2:-1}"
}

# ── Config ───────────────────────────────────────────────────────────

config_init() {
    if [[ ! -d "$CONFIG_DIR" ]]; then
        mkdir -p "$CONFIG_DIR"
    fi
    if [[ ! -f "$CONFIG_FILE" ]]; then
        config_write_defaults
    fi
}

config_write_defaults() {
    cat > "$CONFIG_FILE" <<'EOF'
# hformat configuration
DEFAULT_FSTYPE=fat32
DEFAULT_LABEL=
PARTITION_TABLE=msdos
WIPE_SIGNATURES=true
AUTO_CONFIRM=false
EOF
}

config_load() {
    FSTYPE="$DEFAULT_FSTYPE"
    LABEL="$DEFAULT_LABEL"
    PARTITION_TABLE="$DEFAULT_PARTITION_TABLE"
    WIPE_SIGNATURES="$DEFAULT_WIPE_SIGNATURES"
    AUTO_CONFIRM="$DEFAULT_AUTO_CONFIRM"

    if [[ -f "$CONFIG_FILE" ]]; then
        local tmp_fstype tmp_label tmp_pt tmp_wipe tmp_auto
        tmp_fstype=$(grep -E '^DEFAULT_FSTYPE=' "$CONFIG_FILE" 2>/dev/null | cut -d= -f2- || true)
        tmp_label=$(grep -E '^DEFAULT_LABEL=' "$CONFIG_FILE" 2>/dev/null | cut -d= -f2- || true)
        tmp_pt=$(grep -E '^PARTITION_TABLE=' "$CONFIG_FILE" 2>/dev/null | cut -d= -f2- || true)
        tmp_wipe=$(grep -E '^WIPE_SIGNATURES=' "$CONFIG_FILE" 2>/dev/null | cut -d= -f2- || true)
        tmp_auto=$(grep -E '^AUTO_CONFIRM=' "$CONFIG_FILE" 2>/dev/null | cut -d= -f2- || true)

        [[ -n "$tmp_fstype" ]] && FSTYPE="$tmp_fstype"
        [[ -n "$tmp_label" ]] && LABEL="$tmp_label"
        [[ -n "$tmp_pt" ]] && PARTITION_TABLE="$tmp_pt"
        [[ -n "$tmp_wipe" ]] && WIPE_SIGNATURES="$tmp_wipe"
        [[ -n "$tmp_auto" ]] && AUTO_CONFIRM="$tmp_auto"
    fi
}

config_save() {
    cat > "$CONFIG_FILE" <<EOF
# hformat configuration
DEFAULT_FSTYPE=${FSTYPE}
DEFAULT_LABEL=${LABEL}
PARTITION_TABLE=${PARTITION_TABLE}
WIPE_SIGNATURES=${WIPE_SIGNATURES}
AUTO_CONFIRM=${AUTO_CONFIRM}
EOF
}

# ── Validation ───────────────────────────────────────────────────────

validate_fstype() {
    case "$1" in
        fat32|exfat|ntfs|ext4) return 0 ;;
        *) return 1 ;;
    esac
}

validate_label() {
    local label="$1" fstype="$2"
    [[ -z "$label" ]] && return 0

    case "$fstype" in
        fat32)
            if [[ ${#label} -gt 11 ]]; then
                log_error "FAT32 labels must be 11 characters or fewer (got ${#label})"
                return 1
            fi
            if [[ ! "$label" =~ ^[A-Z0-9\ _-]+$ ]]; then
                log_error "FAT32 labels must be uppercase ASCII, digits, spaces, hyphens, or underscores"
                return 1
            fi
            ;;
        exfat)
            if [[ ${#label} -gt 15 ]]; then
                log_error "exFAT labels must be 15 characters or fewer (got ${#label})"
                return 1
            fi
            ;;
        ntfs)
            if [[ ${#label} -gt 32 ]]; then
                log_error "NTFS labels must be 32 characters or fewer (got ${#label})"
                return 1
            fi
            ;;
        ext4)
            if [[ ${#label} -gt 16 ]]; then
                log_error "ext4 labels must be 16 characters or fewer (got ${#label})"
                return 1
            fi
            ;;
    esac
    return 0
}

# ── Dependencies ─────────────────────────────────────────────────────

check_dependencies() {
    local missing=()
    for cmd in lsblk wipefs sfdisk udevadm; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        die "Missing required commands: ${missing[*]}. Install them with your package manager."
    fi
}

check_mkfs_for_type() {
    local fstype="$1"
    local mkfs_cmd
    case "$fstype" in
        fat32)  mkfs_cmd="mkfs.vfat" ;;
        exfat)  mkfs_cmd="mkfs.exfat" ;;
        ntfs)   mkfs_cmd="mkfs.ntfs" ;;
        ext4)   mkfs_cmd="mkfs.ext4" ;;
    esac
    if ! command -v "$mkfs_cmd" &>/dev/null; then
        die "Missing $mkfs_cmd. Install the appropriate package (e.g., dosfstools, exfatprogs, ntfs-3g, e2fsprogs)."
    fi
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_info "Root privileges required. Escalating with sudo..."
        exec sudo "$0" "$@"
    fi
}

# ── Confirmation ─────────────────────────────────────────────────────

confirm() {
    local prompt="$1"
    if [[ "$OPT_YES" == true || "$AUTO_CONFIRM" == true ]]; then
        return 0
    fi
    printf "${BOLD}%s${RESET} [y/N] " "$prompt"
    local answer
    read -r answer
    case "$answer" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

# ── Disk detection ───────────────────────────────────────────────────

get_partition_path() {
    local device="$1"
    local part_num="${2:-1}"
    local base
    base=$(basename "$device")
    if [[ "$base" =~ [0-9]$ ]]; then
        echo "${device}p${part_num}"
    else
        echo "${device}${part_num}"
    fi
}

is_external_disk() {
    local device="$1"
    local name
    name=$(basename "$device")

    local hotplug tran rm_flag
    hotplug=$(lsblk -dno HOTPLUG "/dev/$name" 2>/dev/null | tr -d ' ')
    tran=$(lsblk -dno TRAN "/dev/$name" 2>/dev/null | tr -d ' ')
    rm_flag=$(lsblk -dno RM "/dev/$name" 2>/dev/null | tr -d ' ')

    if [[ "$hotplug" == "1" ]] || [[ "$tran" == "usb" ]] || [[ "$rm_flag" == "1" ]]; then
        local mount_points
        mount_points=$(lsblk -lno MOUNTPOINT "/dev/$name" 2>/dev/null | grep -v '^$' || true)
        while IFS= read -r mp; do
            case "$mp" in
                /|/boot|/boot/*|/home) return 1 ;;
            esac
        done <<< "$mount_points"
        return 0
    fi
    return 1
}

detect_external_disks() {
    EXTERNAL_DISKS=()
    local disks
    disks=$(lsblk -dno NAME,TYPE 2>/dev/null | awk '$2 == "disk" { print $1 }')

    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        if is_external_disk "/dev/$name"; then
            EXTERNAL_DISKS+=("/dev/$name")
        fi
    done <<< "$disks"
}

get_disk_info() {
    local device="$1"
    local name size model vendor fstype label
    name=$(basename "$device")
    size=$(lsblk -dno SIZE "$device" 2>/dev/null | tr -d ' ')
    model=$(lsblk -dno MODEL "$device" 2>/dev/null | sed 's/^ *//;s/ *$//')
    vendor=$(lsblk -dno VENDOR "$device" 2>/dev/null | sed 's/^ *//;s/ *$//')
    fstype=$(lsblk -no FSTYPE "$device" 2>/dev/null | head -n2 | tail -n1 | tr -d ' ')
    label=$(lsblk -no LABEL "$device" 2>/dev/null | head -n2 | tail -n1 | tr -d ' ')

    local desc="${vendor:+$vendor }${model:-Unknown device}"
    printf "%-12s  %8s  %-30s  %-8s  %s" "$device" "$size" "$desc" "${fstype:-—}" "${label:-—}"
}

list_external_disks() {
    detect_external_disks
    if [[ ${#EXTERNAL_DISKS[@]} -eq 0 ]]; then
        log_warn "No external disks detected. Plug in a USB drive and try again."
        return 1
    fi

    printf "\n${BOLD}%-12s  %8s  %-30s  %-8s  %s${RESET}\n" "DEVICE" "SIZE" "MODEL" "FS" "LABEL"
    printf "%s\n" "────────────────────────────────────────────────────────────────────────────────"
    for dev in "${EXTERNAL_DISKS[@]}"; do
        get_disk_info "$dev"
        printf "\n"
    done
    printf "\n"
}

# ── Formatting ───────────────────────────────────────────────────────

unmount_disk() {
    local device="$1"
    local partitions
    partitions=$(lsblk -lno NAME,MOUNTPOINT "$device" 2>/dev/null | awk '$2 != "" { print "/dev/"$1 }')

    if [[ -z "$partitions" ]]; then
        return 0
    fi

    while IFS= read -r part; do
        [[ -z "$part" ]] && continue
        log_info "Unmounting $part..."
        if [[ "$OPT_DRY_RUN" == true ]]; then
            log_info "[dry-run] Would unmount $part"
            continue
        fi
        if ! umount "$part" 2>/dev/null; then
            log_error "Failed to unmount $part. Processes using it:"
            fuser -m "$part" 2>/dev/null || true
            return 1
        fi
    done <<< "$partitions"
    return 0
}

wipe_disk() {
    local device="$1"
    if [[ "$WIPE_SIGNATURES" != "true" ]]; then
        return 0
    fi
    if [[ "$OPT_DRY_RUN" == true ]]; then
        log_info "[dry-run] Would wipe filesystem signatures on $device"
        return 0
    fi
    log_info "Wiping filesystem signatures on $device..."
    wipefs --all --force "$device" &>/dev/null
}

create_partition_table() {
    local device="$1" fstype="$2"
    local type_code=""

    if [[ "$PARTITION_TABLE" == "msdos" ]]; then
        case "$fstype" in
            fat32)  type_code="c" ;;
            exfat)  type_code="7" ;;
            ntfs)   type_code="7" ;;
            ext4)   type_code="83" ;;
        esac
    fi

    if [[ "$OPT_DRY_RUN" == true ]]; then
        log_info "[dry-run] Would create $PARTITION_TABLE partition table on $device (type=$type_code)"
        return 0
    fi

    log_info "Creating $PARTITION_TABLE partition table on $device..."

    if [[ "$PARTITION_TABLE" == "msdos" && -n "$type_code" ]]; then
        echo ",,${type_code};" | sfdisk --force --label dos "$device" &>/dev/null
    else
        echo ",,;" | sfdisk --force --label gpt "$device" &>/dev/null
    fi

    udevadm settle --timeout=5 2>/dev/null || sleep 2
    blockdev --rereadpt "$device" 2>/dev/null || true
    udevadm settle --timeout=5 2>/dev/null || sleep 2

    local part
    part=$(get_partition_path "$device")
    local retries=0
    while [[ ! -b "$part" && $retries -lt 5 ]]; do
        sleep 1
        ((retries++))
    done

    if [[ ! -b "$part" ]]; then
        die "Partition $part did not appear after creating partition table on $device"
    fi
}

format_partition() {
    local partition="$1" fstype="$2" label="$3"

    if [[ "$OPT_DRY_RUN" == true ]]; then
        log_info "[dry-run] Would format $partition as $fstype${label:+ with label '$label'}"
        return 0
    fi

    log_info "Formatting $partition as $fstype${label:+ with label '$label'}..."

    case "$fstype" in
        fat32)
            local cmd=(mkfs.vfat -F 32)
            [[ -n "$label" ]] && cmd+=(-n "$label")
            cmd+=("$partition")
            "${cmd[@]}" &>/dev/null
            ;;
        exfat)
            local cmd=(mkfs.exfat)
            [[ -n "$label" ]] && cmd+=(-L "$label")
            cmd+=("$partition")
            "${cmd[@]}" &>/dev/null
            ;;
        ntfs)
            local cmd=(mkfs.ntfs --fast)
            [[ -n "$label" ]] && cmd+=(-L "$label")
            cmd+=("$partition")
            "${cmd[@]}" &>/dev/null
            ;;
        ext4)
            local cmd=(mkfs.ext4 -F)
            [[ -n "$label" ]] && cmd+=(-L "$label")
            cmd+=("$partition")
            "${cmd[@]}" &>/dev/null
            ;;
    esac
}

format_disk() {
    local device="$1" fstype="$2" label="$3"

    if [[ ! -b "$device" ]]; then
        log_error "$device does not exist or is not a block device"
        return 1
    fi

    local name
    name=$(basename "$device")
    if ! is_external_disk "$device"; then
        log_error "$device appears to be an internal disk. Refusing to format."
        return 1
    fi

    printf "\n"
    printf "${BOLD}Disk:${RESET}       %s\n" "$(get_disk_info "$device")"
    printf "${BOLD}Format:${RESET}     %s\n" "$fstype"
    printf "${BOLD}Label:${RESET}      %s\n" "${label:-<none>}"
    printf "${BOLD}Partition:${RESET}  %s\n" "$PARTITION_TABLE"
    printf "\n"

    printf "${RED}${BOLD}ALL DATA ON $device WILL BE PERMANENTLY DESTROYED.${RESET}\n"
    if ! confirm "Proceed with formatting $device?"; then
        log_warn "Skipped $device"
        return 1
    fi

    if ! unmount_disk "$device"; then
        log_error "Could not unmount $device. Skipping."
        return 1
    fi

    wipe_disk "$device"
    create_partition_table "$device" "$fstype"

    local partition
    partition=$(get_partition_path "$device")

    if ! format_partition "$partition" "$fstype" "$label"; then
        log_error "Failed to format $partition"
        return 1
    fi

    log_success "Successfully formatted $device ($partition) as $fstype"
    return 0
}

# ── TUI Config ───────────────────────────────────────────────────────

check_whiptail() {
    if ! command -v whiptail &>/dev/null; then
        die "whiptail is required for the config interface. Install it with: sudo apt install whiptail"
    fi
}

tui_fstype_menu() {
    local current="$FSTYPE"
    local result
    result=$(whiptail --backtitle "hformat Configuration" \
        --title "Default Filesystem" \
        --radiolist "Select the default filesystem type:" 14 50 4 \
        "fat32"  "FAT32 (most compatible)"      "$([ "$current" = "fat32" ]  && echo ON || echo OFF)" \
        "exfat"  "exFAT (large files, USB)"      "$([ "$current" = "exfat" ]  && echo ON || echo OFF)" \
        "ntfs"   "NTFS (Windows)"                "$([ "$current" = "ntfs" ]   && echo ON || echo OFF)" \
        "ext4"   "ext4 (Linux)"                  "$([ "$current" = "ext4" ]   && echo ON || echo OFF)" \
        3>&1 1>&2 2>&3) || return
    if [[ -n "$result" ]]; then
        FSTYPE="$result"
        config_save
    fi
}

tui_label_input() {
    local result
    result=$(whiptail --backtitle "hformat Configuration" \
        --title "Default Label" \
        --inputbox "Enter default volume label (leave empty for none):" 10 50 \
        "$LABEL" 3>&1 1>&2 2>&3) || return
    if validate_label "$result" "$FSTYPE"; then
        LABEL="$result"
        config_save
    else
        whiptail --backtitle "hformat Configuration" \
            --title "Invalid Label" \
            --msgbox "The label you entered is not valid for $FSTYPE." 8 50
    fi
}

tui_partition_table_menu() {
    local current="$PARTITION_TABLE"
    local result
    result=$(whiptail --backtitle "hformat Configuration" \
        --title "Partition Table" \
        --radiolist "Select partition table type:" 12 50 2 \
        "msdos"  "MBR (most compatible)"  "$([ "$current" = "msdos" ] && echo ON || echo OFF)" \
        "gpt"    "GPT (modern, >2TB)"     "$([ "$current" = "gpt" ]   && echo ON || echo OFF)" \
        3>&1 1>&2 2>&3) || return
    if [[ -n "$result" ]]; then
        PARTITION_TABLE="$result"
        config_save
    fi
}

tui_toggle() {
    local key="$1" title="$2" description="$3"
    local current="${!key}"
    local prompt
    if [[ "$current" == "true" ]]; then
        prompt="$description\n\nCurrently: ENABLED\n\nDisable it?"
    else
        prompt="$description\n\nCurrently: DISABLED\n\nEnable it?"
    fi

    if whiptail --backtitle "hformat Configuration" \
        --title "$title" \
        --yesno "$prompt" 12 50 3>&1 1>&2 2>&3; then
        if [[ "$current" == "true" ]]; then
            eval "$key=false"
        else
            eval "$key=true"
        fi
        config_save
    fi
}

tui_reset_defaults() {
    if whiptail --backtitle "hformat Configuration" \
        --title "Reset to Defaults" \
        --yesno "Reset all settings to their default values?" 8 50 3>&1 1>&2 2>&3; then
        config_write_defaults
        config_load
    fi
}

tui_show_current() {
    whiptail --backtitle "hformat Configuration" \
        --title "Current Settings" \
        --msgbox "$(printf "Filesystem:       %s\nDefault Label:    %s\nPartition Table:  %s\nWipe Signatures:  %s\nAuto Confirm:     %s" \
            "$FSTYPE" "${LABEL:-<none>}" "$PARTITION_TABLE" "$WIPE_SIGNATURES" "$AUTO_CONFIRM")" \
        14 50
}

tui_main_menu() {
    check_whiptail
    while true; do
        local choice
        choice=$(whiptail --backtitle "hformat Configuration" \
            --title "Settings" \
            --menu "Configure default formatting settings:" 18 55 8 \
            "1" "Default Filesystem    [$FSTYPE]" \
            "2" "Default Label         [${LABEL:-<none>}]" \
            "3" "Partition Table       [$PARTITION_TABLE]" \
            "4" "Wipe Signatures       [$WIPE_SIGNATURES]" \
            "5" "Auto Confirm          [$AUTO_CONFIRM]" \
            "6" "View Current Settings" \
            "7" "Reset to Defaults" \
            "8" "Exit" \
            3>&1 1>&2 2>&3) || break

        case "$choice" in
            1) tui_fstype_menu ;;
            2) tui_label_input ;;
            3) tui_partition_table_menu ;;
            4) tui_toggle WIPE_SIGNATURES "Wipe Signatures" "Erase existing filesystem signatures before formatting.\nPrevents stale signatures from confusing the OS." ;;
            5) tui_toggle AUTO_CONFIRM "Auto Confirm" "Skip confirmation prompts by default.\nSame as always passing -y." ;;
            6) tui_show_current ;;
            7) tui_reset_defaults ;;
            8) break ;;
        esac
    done
}

# ── Help / Version ───────────────────────────────────────────────────

show_help() {
    printf "%b" "\
${BOLD}hformat${RESET} - Format external disks

${BOLD}Usage:${RESET}
  hformat [options] <device> [device...]
  hformat --all [options]
  hformat config
  hformat list

${BOLD}Options:${RESET}
  -n, --name LABEL   Set volume label
  -t, --type TYPE    Filesystem type: fat32, exfat, ntfs, ext4 (default: fat32)
  -a, --all          Format all detected external disks
  -y, --yes          Skip confirmation prompts
      --dry-run      Show what would be done without doing it
  -h, --help         Show this help
  -v, --version      Show version

${BOLD}Subcommands:${RESET}
  config             Open configuration interface
  list               List detected external disks

${BOLD}Examples:${RESET}
  hformat /dev/sdb                    Format /dev/sdb as FAT32
  hformat -t ntfs -n BACKUP /dev/sdb  Format as NTFS with label BACKUP
  hformat --all -y                    Format all external disks, no prompts
  hformat config                      Open settings UI
"
}

show_version() {
    echo "hformat $VERSION"
}

# ── Main ─────────────────────────────────────────────────────────────

main() {
    config_init
    config_load

    if [[ $# -eq 0 ]]; then
        show_help
        printf "\n"
        log_info "Detected external disks:"
        list_external_disks || true
        exit 0
    fi

    case "${1:-}" in
        config)
            tui_main_menu
            exit 0
            ;;
        list)
            list_external_disks
            exit 0
            ;;
        help|--help|-h)
            show_help
            exit 0
            ;;
        version|--version|-v)
            show_version
            exit 0
            ;;
    esac

    check_dependencies

    local original_args=("$@")

    local args
    args=$(getopt -o n:t:ayvh -l name:,type:,all,yes,help,version,dry-run -n "$SCRIPT_NAME" -- "$@") || {
        show_help
        exit 1
    }
    eval set -- "$args"

    while true; do
        case "$1" in
            -n|--name)    OPT_NAME="$2"; shift 2 ;;
            -t|--type)    OPT_TYPE="$2"; shift 2 ;;
            -a|--all)     OPT_ALL=true; shift ;;
            -y|--yes)     OPT_YES=true; shift ;;
            --dry-run)    OPT_DRY_RUN=true; shift ;;
            -h|--help)    show_help; exit 0 ;;
            -v|--version) show_version; exit 0 ;;
            --)           shift; break ;;
            *)            break ;;
        esac
    done

    DEVICES=("$@")

    if [[ "$OPT_ALL" == true && ${#DEVICES[@]} -gt 0 ]]; then
        die "Cannot use --all together with explicit device arguments."
    fi

    if [[ "$OPT_ALL" == false && ${#DEVICES[@]} -eq 0 ]]; then
        show_help
        exit 1
    fi

    local use_fstype="${OPT_TYPE:-$FSTYPE}"
    local use_label="${OPT_NAME:-$LABEL}"

    if ! validate_fstype "$use_fstype"; then
        die "Unsupported filesystem: $use_fstype. Supported: fat32, exfat, ntfs, ext4."
    fi

    if [[ -n "$use_label" ]]; then
        validate_label "$use_label" "$use_fstype" || exit 1
    fi

    check_mkfs_for_type "$use_fstype"
    check_root "${original_args[@]}"

    local targets=()
    if [[ "$OPT_ALL" == true ]]; then
        detect_external_disks
        if [[ ${#EXTERNAL_DISKS[@]} -eq 0 ]]; then
            die "No external disks detected. Plug in a USB drive and try again."
        fi
        targets=("${EXTERNAL_DISKS[@]}")
        log_info "Found ${#targets[@]} external disk(s):"
        list_external_disks
    else
        for dev in "${DEVICES[@]}"; do
            if [[ ! "$dev" =~ ^/dev/ ]]; then
                dev="/dev/$dev"
            fi
            targets+=("$dev")
        done
    fi

    local success=0 fail=0
    for dev in "${targets[@]}"; do
        if format_disk "$dev" "$use_fstype" "$use_label"; then
            success=$((success + 1))
        else
            fail=$((fail + 1))
        fi
    done

    printf "\n"
    if [[ $fail -eq 0 ]]; then
        log_success "Done. $success disk(s) formatted successfully."
    else
        log_warn "Done. $success succeeded, $fail failed."
        exit 1
    fi
}

main "$@"
