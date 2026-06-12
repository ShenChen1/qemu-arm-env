#!/usr/bin/env bash
# =============================================================================
# build-rootfs.sh — Build a Debian minbase ext4 rootfs for AArch64 QEMU
#
# Usage: sudo ./scripts/build-rootfs.sh <output_image> [size_mb]
#   output_image : Path to the output ext4 image (e.g. obj/rootfs.ext4)
#   size_mb      : Image size in MB (default: 1024)
#
# Features:
#   - Caches debootstrap base system as tarball for fast rebuilds (~10s vs ~3min)
#   - Uses China mirror (HTTP) for speed, falls back to official if needed
#
# Requires: debootstrap, mkfs.ext4, qemu-aarch64 (binfmt_misc registered)
# =============================================================================
set -euo pipefail

# ── Utility functions ────────────────────────────────────────────────────────
err()  { printf 'ERROR: %s\n' "$*" >&2; }
die()  { err "$@"; exit 1; }
log()  { printf '==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }

# ── Constants ────────────────────────────────────────────────────────────────
readonly DEBIAN_SUITE="bookworm"
# China HTTP mirror for debootstrap (fast, no cert issues)
readonly DEBOOTSTRAP_MIRROR="http://mirrors.ustc.edu.cn/debian"
# Fallback mirror if China mirror has missing packages
readonly DEBOOTSTRAP_FALLBACK="http://deb.debian.org/debian"
# China mirror for rootfs apt sources (in-VM package installs)
readonly APT_MIRROR="http://mirrors.ustc.edu.cn/debian"
readonly QEMU_USER_BIN="/usr/bin/qemu-aarch64"
readonly ROOT_PASSWORD="root"
readonly VM_HOSTNAME="arm64-dev"
readonly -a REQUIRED_TOOLS=(debootstrap mkfs.ext4)

# Cache directory and base tarball path (relative to script caller's cwd)
readonly CACHE_DIR="obj"
readonly BASE_TARBALL="${CACHE_DIR}/rootfs-base.tar"

# ── Packages to install inside rootfs ────────────────────────────────────────
# Core diagnostics and eBPF tooling; no compilers (host-driven workflow)
readonly -a INSTALL_PACKAGES=(
    # system essentials
    systemd systemd-sysv dbus udev
    # network
    openssh-server iproute2 iputils-ping net-tools
    # debug & trace arsenal
    strace tcpdump gdb-multiarch gdbserver
    # eBPF tooling
    bpftool
    # performance
    linux-perf
    # filesystem & misc
    kmod procps less vim-tiny ca-certificates curl
)

# ── Argument parsing ────────────────────────────────────────────────────────
OUTPUT_IMAGE="${1:?Usage: ${BASH_SOURCE[0]} <output_image> [size_mb]}"
SIZE_MB="${2:-1024}"

# ── Pre-flight checks ───────────────────────────────────────────────────────
check_prerequisites() {
    (( EUID == 0 )) || die "This script must be run as root (use sudo)."

    for tool in "${REQUIRED_TOOLS[@]}"; do
        command -v "$tool" &>/dev/null || \
            die "Required tool '${tool}' not found. Install it first."
    done

    [[ -x "$QEMU_USER_BIN" ]] || \
        die "${QEMU_USER_BIN} not found. Install qemu-user or qemu-user-static."

    if [[ ! -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ]]; then
        warn "binfmt_misc for qemu-aarch64 not registered."
        warn "Foreign chroot may fail. Register it or install qemu-user-binfmt."
    fi
}

# ── Debootstrap with cache ──────────────────────────────────────────────────
# First run: debootstrap + second-stage → save as tarball (~3 min)
# Subsequent runs: extract tarball → done (~10 sec)
run_debootstrap_cached() {
    local rootfs="$1"

    if [[ -f "$BASE_TARBALL" ]]; then
        log "[CACHE HIT] Extracting base system from ${BASE_TARBALL}"
        tar xf "$BASE_TARBALL" -C "$rootfs"
        # Ensure qemu-aarch64 is present for chroot operations
        cp "$QEMU_USER_BIN" "${rootfs}/usr/bin/qemu-aarch64"
        return 0
    fi

    log "[CACHE MISS] Running full debootstrap (result will be cached)"

    # Try China mirror first, fall back to official on failure
    local mirror="$DEBOOTSTRAP_MIRROR"
    if ! debootstrap --arch=arm64 --foreign --variant=minbase \
            "$DEBIAN_SUITE" "$rootfs" "$mirror" 2>&1; then
        log "China mirror failed, falling back to official mirror"
        # Clean partial debootstrap
        rm -rf "${rootfs:?}"/*
        mirror="$DEBOOTSTRAP_FALLBACK"
        debootstrap --arch=arm64 --foreign --variant=minbase \
            "$DEBIAN_SUITE" "$rootfs" "$mirror"
    fi

    # Second stage (runs under qemu-user emulation)
    cp "$QEMU_USER_BIN" "${rootfs}/usr/bin/qemu-aarch64"
    chroot "$rootfs" /debootstrap/debootstrap --second-stage

    # Save base system as tarball for future rebuilds
    log "Caching base system to ${BASE_TARBALL}"
    tar cf "$BASE_TARBALL" -C "$rootfs" .
    log "Cache saved: $(du -h "$BASE_TARBALL" | cut -f1)"
}

# ── Build rootfs ─────────────────────────────────────────────────────────────
build_rootfs() {
    ROOTFS_BUILD_DIR=$(mktemp -d)
    local start_time=$SECONDS

    log "[1/6] Creating sparse image: ${OUTPUT_IMAGE} (${SIZE_MB}MB)"
    mkdir -p "$CACHE_DIR"
    truncate -s "${SIZE_MB}M" "$OUTPUT_IMAGE"
    mkfs.ext4 -q -F -L rootfs "$OUTPUT_IMAGE"

    log "[2/6] Mounting image"
    mount -o loop "$OUTPUT_IMAGE" "$ROOTFS_BUILD_DIR"

    log "[3/6] Bootstrapping base system"
    run_debootstrap_cached "$ROOTFS_BUILD_DIR"

    log "[4/6] Configuring system"
    configure_system "$ROOTFS_BUILD_DIR"

    log "[5/6] Installing packages"
    install_packages "$ROOTFS_BUILD_DIR"

    log "[6/6] Cleaning up rootfs caches"
    chroot "$ROOTFS_BUILD_DIR" apt-get clean
    rm -rf "${ROOTFS_BUILD_DIR}/var/lib/apt/lists/"*
    rm -rf "${ROOTFS_BUILD_DIR}/var/cache/apt/"*
    rm -f "${ROOTFS_BUILD_DIR}/usr/bin/qemu-aarch64"

    log "Unmounting"
    umount "$ROOTFS_BUILD_DIR"
    rm -rf "$ROOTFS_BUILD_DIR"
    ROOTFS_BUILD_DIR=""

    local elapsed=$(( SECONDS - start_time ))
    log "Done! Rootfs image: ${OUTPUT_IMAGE} (${elapsed}s)"
    ls -lh "$OUTPUT_IMAGE"
}

# ── System configuration ────────────────────────────────────────────────────
configure_system() {
    local rootfs="$1"

    # hostname
    printf '%s\n' "$VM_HOSTNAME" > "${rootfs}/etc/hostname"
    cat > "${rootfs}/etc/hosts" <<EOF
127.0.0.1   localhost
127.0.1.1   ${VM_HOSTNAME}
EOF

    # root password (piped via stdin to avoid exposing in process list)
    printf 'root:%s\n' "${ROOT_PASSWORD}" | chroot "$rootfs" chpasswd

    # fstab — rootfs + 9p host share
    cat > "${rootfs}/etc/fstab" <<EOF
# <fs>          <mountpoint>  <type>  <options>               <dump> <pass>
/dev/vda        /             ext4    errors=remount-ro       0      1
hostshare       /mnt/host     9p      trans=virtio,version=9p2000.L,msize=104857600,nofail 0 0
tmpfs           /tmp          tmpfs   defaults                0      0
EOF

    # Create the 9p mount point
    mkdir -p "${rootfs}/mnt/host"

    # Enable serial console (ttyAMA0 for QEMU virt)
    chroot "$rootfs" systemctl enable serial-getty@ttyAMA0.service 2>/dev/null || true

    # SSH: permit root login with password (dev environment only)
    mkdir -p "${rootfs}/etc/ssh/sshd_config.d"
    cat > "${rootfs}/etc/ssh/sshd_config.d/dev.conf" <<EOF
PermitRootLogin yes
PasswordAuthentication yes
EOF

    # DNS resolver (QEMU user-mode NAT)
    cat > "${rootfs}/etc/resolv.conf" <<EOF
nameserver 10.0.2.3
EOF

    # Auto-mount 9p on boot via systemd mount unit
    mkdir -p "${rootfs}/etc/systemd/system"
    cat > "${rootfs}/etc/systemd/system/mnt-host.mount" <<EOF
[Unit]
Description=Mount 9p host share
After=local-fs.target

[Mount]
What=hostshare
Where=/mnt/host
Type=9p
Options=trans=virtio,version=9p2000.L,msize=104857600,nofail

[Install]
WantedBy=multi-user.target
EOF
    chroot "$rootfs" systemctl enable mnt-host.mount 2>/dev/null || true
}

# ── Package installation ────────────────────────────────────────────────────
install_packages() {
    local rootfs="$1"

    # Use host DNS during build (10.0.2.3 only works inside QEMU)
    cp /etc/resolv.conf "${rootfs}/etc/resolv.conf"

    # Set up APT sources (China HTTP mirror, no cert needed)
    cat > "${rootfs}/etc/apt/sources.list" <<EOF
deb ${APT_MIRROR} ${DEBIAN_SUITE} main contrib non-free non-free-firmware
deb ${APT_MIRROR} ${DEBIAN_SUITE}-updates main contrib non-free non-free-firmware
EOF

    # Prevent interactive prompts
    export DEBIAN_FRONTEND=noninteractive

    chroot "$rootfs" apt-get update -qq
    chroot "$rootfs" apt-get install -y --no-install-recommends "${INSTALL_PACKAGES[@]}"

    # Restore QEMU user-mode DNS for runtime
    cat > "${rootfs}/etc/resolv.conf" <<EOF
nameserver 10.0.2.3
EOF
}

# ── Cleanup handler ─────────────────────────────────────────────────────────
cleanup() {
    local exit_code=$?
    if [[ -n "${ROOTFS_BUILD_DIR:-}" ]]; then
        warn "Cleaning up (exit_code=${exit_code})..."
        if mountpoint -q "$ROOTFS_BUILD_DIR" 2>/dev/null; then
            umount "$ROOTFS_BUILD_DIR" || warn "Failed to unmount ${ROOTFS_BUILD_DIR}"
        fi
        rm -rf "$ROOTFS_BUILD_DIR"
    fi
    # Remove partial/corrupt image on failure
    if (( exit_code != 0 )) && [[ -f "${OUTPUT_IMAGE:-}" ]]; then
        rm -f "$OUTPUT_IMAGE"
        warn "Removed partial image: ${OUTPUT_IMAGE}"
    fi
}

# ── Main ─────────────────────────────────────────────────────────────────────
ROOTFS_BUILD_DIR=""
trap cleanup EXIT

check_prerequisites
build_rootfs
