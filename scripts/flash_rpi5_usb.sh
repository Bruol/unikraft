#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

FIRMWARE_VERSION=${FIRMWARE_VERSION:-master}
FIRMWARE_BASE_URL="https://raw.githubusercontent.com/raspberrypi/firmware/${FIRMWARE_VERSION}/boot"
STAGING_ROOT="${REPO_ROOT}/build/rpi5_usb"
BOOT_DIR="${STAGING_ROOT}/bootfs"
VOLUME_LABEL=${VOLUME_LABEL:-RPI5BOOT}
KERNEL_DEST_NAME="kernel_2712.img"

DEVICE=""
KERNEL_PATH=""
AUTO_YES=0
KEEP_STAGING=0

RSYNC_EXCLUDES=(
    --exclude='.Spotlight-V100/'
    --exclude='.Trashes/'
    --exclude='.fseventsd/'
)

usage() {
    cat <<EOF
Usage: $(basename "$0") --kernel <kernel.img|kernel.elf> --device <disk>

Builds a Raspberry Pi 5 bootable USB stick for bare-metal work by:
  1. Downloading the Pi 5 boot firmware files
  2. Converting an ELF kernel to a raw image when needed
  3. Partitioning the target USB device as FAT32
  4. Copying firmware, config.txt, and the kernel image onto the USB stick

Options:
  --kernel PATH            Kernel image or ELF file to install
  --device PATH            Whole-disk device to erase, e.g. /dev/disk4 or /dev/sdb
  --firmware-version REF   Firmware branch/tag/commit to download (default: ${FIRMWARE_VERSION})
  --yes                    Skip the destructive-action confirmation prompt
  --keep-staging           Keep staged firmware under ${STAGING_ROOT}
  --help                   Show this help

Examples:
  $(basename "$0") --kernel build/kernel_2712.img --device /dev/disk4
  $(basename "$0") --kernel build/kernel.elf --device /dev/sdb --firmware-version master
EOF
}

log() {
    printf '[flash-rpi5] %s\n' "$*"
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

confirm() {
    local answer

    if [ "${AUTO_YES}" -eq 1 ]; then
        return 0
    fi

    printf 'About to erase %s and make it bootable for Raspberry Pi 5. Continue? [y/N] ' "${DEVICE}" >&2
    read -r answer
    case "${answer}" in
        y|Y|yes|YES)
            return 0
            ;;
        *)
            die "aborted"
            ;;
    esac
}

download_file() {
    local relative_path=$1
    local output_path="${BOOT_DIR}/${relative_path}"

    mkdir -p "$(dirname "${output_path}")"
    curl -fsSL --output "${output_path}" "${FIRMWARE_BASE_URL}/${relative_path}"
}

find_objcopy() {
    if [ -n "${OBJCOPY:-}" ] && command -v "${OBJCOPY}" >/dev/null 2>&1; then
        printf '%s\n' "${OBJCOPY}"
        return 0
    fi

    local candidate
    for candidate in \
        llvm-objcopy \
        aarch64-none-elf-objcopy \
        aarch64-elf-objcopy \
        gobjcopy \
        objcopy
    do
        if command -v "${candidate}" >/dev/null 2>&1; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done

    return 1
}

is_elf_kernel() {
    if command -v file >/dev/null 2>&1; then
        file -b "${KERNEL_PATH}" | grep -q 'ELF'
        return $?
    fi

    case "${KERNEL_PATH}" in
        *.elf|*.ELF)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

stage_firmware() {
    log "staging Raspberry Pi 5 firmware into ${BOOT_DIR}"
    rm -rf "${BOOT_DIR}"
    mkdir -p "${BOOT_DIR}"

    # Pi 5 boots from EEPROM, so we only fetch the files still relevant to its FAT boot volume.
    download_file "LICENCE.broadcom"
    download_file "bcm2712-rpi-5-b.dtb"
    download_file "overlays/vc4-kms-v3d-pi5.dtbo"
}

stage_kernel() {
    local destination="${BOOT_DIR}/${KERNEL_DEST_NAME}"

    [ -f "${KERNEL_PATH}" ] || die "kernel file not found: ${KERNEL_PATH}"

    if is_elf_kernel; then
        local objcopy
        objcopy=$(find_objcopy) || die "kernel appears to be ELF, but no objcopy was found"
        log "converting ELF kernel to ${KERNEL_DEST_NAME} with ${objcopy}"
        "${objcopy}" -O binary "${KERNEL_PATH}" "${destination}"
    else
        log "copying raw kernel image to ${KERNEL_DEST_NAME}"
        cp "${KERNEL_PATH}" "${destination}"
    fi
}

write_config() {
    cat > "${BOOT_DIR}/config.txt" <<'EOF'
# Raspberry Pi 5 requires a non-empty config.txt on the boot partition.
arm_64bit=1
kernel=kernel_2712.img
device_tree=bcm2712-rpi-5-b.dtb
enable_jtag_gpio=1
usb_max_current_enable=1

EOF
}

darwin_partition() {
    local partition="${DEVICE}s1"
    local mount_point

    require_cmd diskutil
    require_cmd rsync

    log "partitioning ${DEVICE} as MBR/FAT32"
    sudo diskutil unmountDisk force "${DEVICE}" >/dev/null 2>&1 || true
    sudo diskutil partitionDisk "${DEVICE}" 1 MBRFormat "MS-DOS FAT32" "${VOLUME_LABEL}" "100%" >/dev/null
    sleep 2

    mount_point=$(diskutil info "${partition}" | awk -F': *' '/Mount Point/ {print $2; exit}')
    if [ -z "${mount_point}" ] || [ "${mount_point}" = "Not mounted" ]; then
        sudo diskutil mount "${partition}" >/dev/null
        mount_point=$(diskutil info "${partition}" | awk -F': *' '/Mount Point/ {print $2; exit}')
    fi
    [ -n "${mount_point}" ] || die "failed to determine mount point for ${partition}"

    log "copying boot files to ${mount_point}"
    rsync -rltD --delete --no-perms --no-owner --no-group "${RSYNC_EXCLUDES[@]}" "${BOOT_DIR}/" "${mount_point}/"
    sync
    diskutil eject "${DEVICE}" >/dev/null
}

linux_partition_name() {
    case "${DEVICE}" in
        *[0-9])
            printf '%sp1\n' "${DEVICE}"
            ;;
        *)
            printf '%s1\n' "${DEVICE}"
            ;;
    esac
}

linux_partition() {
    local partition
    local mount_point="${STAGING_ROOT}/mnt"

    require_cmd parted
    require_cmd mkfs.vfat
    require_cmd mount
    require_cmd umount
    require_cmd rsync

    partition=$(linux_partition_name)

    log "partitioning ${DEVICE} as MBR/FAT32"
    sudo umount "${partition}" >/dev/null 2>&1 || true
    sudo parted -s "${DEVICE}" mklabel msdos
    sudo parted -s "${DEVICE}" mkpart primary fat32 1MiB 100%
    sudo parted -s "${DEVICE}" set 1 boot on
    sudo mkfs.vfat -F 32 -n "${VOLUME_LABEL}" "${partition}" >/dev/null

    rm -rf "${mount_point}"
    mkdir -p "${mount_point}"

    log "copying boot files to ${partition}"
    sudo mount "${partition}" "${mount_point}"
    sudo rsync -rltD --delete --no-perms --no-owner --no-group "${RSYNC_EXCLUDES[@]}" "${BOOT_DIR}/" "${mount_point}/"
    sync
    sudo umount "${mount_point}"
}

print_device_hint() {
    case "$(uname -s)" in
        Darwin)
            printf 'Available disks:\n' >&2
            diskutil list external physical >&2 || true
            ;;
        Linux)
            if command -v lsblk >/dev/null 2>&1; then
                printf 'Available removable-style block devices:\n' >&2
                lsblk -dpno NAME,SIZE,MODEL,TRAN >&2 || true
            fi
            ;;
    esac
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --kernel)
                [ $# -ge 2 ] || die "--kernel requires a value"
                KERNEL_PATH=$2
                shift 2
                ;;
            --device)
                [ $# -ge 2 ] || die "--device requires a value"
                DEVICE=$2
                shift 2
                ;;
            --firmware-version)
                [ $# -ge 2 ] || die "--firmware-version requires a value"
                FIRMWARE_VERSION=$2
                FIRMWARE_BASE_URL="https://raw.githubusercontent.com/raspberrypi/firmware/${FIRMWARE_VERSION}/boot"
                shift 2
                ;;
            --yes)
                AUTO_YES=1
                shift
                ;;
            --keep-staging)
                KEEP_STAGING=1
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                die "unknown argument: $1"
                ;;
        esac
    done
}

validate_inputs() {
    [ -e "${DEVICE}" ] || die "device does not exist: ${DEVICE}"

    case "$(uname -s)" in
        Darwin)
            case "${DEVICE}" in
                /dev/disk[0-9]*)
                    case "${DEVICE}" in
                        *s[0-9])
                            die "use the whole disk (for example /dev/disk4), not a partition (${DEVICE})"
                            ;;
                    esac
                    ;;
                *)
                    die "expected a macOS whole-disk path like /dev/disk4, got: ${DEVICE}"
                    ;;
            esac
            ;;
        Linux)
            case "${DEVICE}" in
                /dev/*)
                    ;;
                *)
                    die "expected a block-device path like /dev/sdb or /dev/nvme0n1, got: ${DEVICE}"
                    ;;
            esac
            ;;
    esac
}

main() {
    parse_args "$@"

    [ -n "${KERNEL_PATH}" ] || {
        usage
        print_device_hint
        die "--kernel is required"
    }

    [ -n "${DEVICE}" ] || {
        usage
        print_device_hint
        die "--device is required"
    }

    require_cmd curl
    require_cmd uname
    validate_inputs
    confirm

    stage_firmware
    stage_kernel
    write_config

    case "$(uname -s)" in
        Darwin)
            darwin_partition
            ;;
        Linux)
            linux_partition
            ;;
        *)
            die "unsupported host OS: $(uname -s)"
            ;;
    esac

    if [ "${KEEP_STAGING}" -eq 0 ]; then
        rm -rf "${BOOT_DIR}" "${STAGING_ROOT}/mnt"
    fi

    log "USB stick is ready. Insert it into the Raspberry Pi 5 and power on."
}

main "$@"
