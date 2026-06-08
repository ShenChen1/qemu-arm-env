#
# GNUmakefile — QEMU AArch64 Development Environment
#
# Build pipeline: kernel → rootfs → qemu
#
# This makefile system follows the structuring conventions
# recommended by Peter Miller in his excellent paper:
#
#	Recursive Make Considered Harmful
#	http://aegis.sourceforge.net/auug97.pdf
#

# ═══════════════════════════════════════════════════════════════════════════
# Directories & Paths
# ═══════════════════════════════════════════════════════════════════════════
OBJDIR       := obj
KERNEL_DIR   := linux
KERNEL_IMAGE := $(KERNEL_DIR)/arch/arm64/boot/Image
ROOTFS_IMG   := $(OBJDIR)/rootfs.ext4
SHARE_DIR    := share
SCRIPTS_DIR  := scripts
KERNEL_CONFIG := $(SCRIPTS_DIR)/kernel.config

# ═══════════════════════════════════════════════════════════════════════════
# Verbosity: 'make V=1' for verbose, 'make V=0' (default) for quiet
# ═══════════════════════════════════════════════════════════════════════════
V ?= 0
ifeq ($(V),1)
override V =
endif
ifeq ($(V),0)
override V = @
endif

# ═══════════════════════════════════════════════════════════════════════════
# Toolchain
# ═══════════════════════════════════════════════════════════════════════════
QEMU         := qemu-system-aarch64
GCCPREFIX    := aarch64-linux-gnu-
CC           := $(GCCPREFIX)gcc -pipe
AS           := $(GCCPREFIX)as
AR           := $(GCCPREFIX)ar
LD           := $(GCCPREFIX)ld
OBJCOPY      := $(GCCPREFIX)objcopy
OBJDUMP      := $(GCCPREFIX)objdump
NM           := $(GCCPREFIX)nm
GDB          := $(GCCPREFIX)gdb

# ═══════════════════════════════════════════════════════════════════════════
# Tunable Parameters
# ═══════════════════════════════════════════════════════════════════════════
CPUS         ?= 4
MEM          ?= 512M
SSH_PORT     ?= 2222
ROOTFS_SIZE  ?= 1024
KERNEL_JOBS  ?= $(shell nproc)

# Port derivation for GDB (unique per user)
GDBPORT      := $(shell expr `id -u` % 5000 + 25000)
DEBUGPORT    := $(shell expr `id -u` % 5000 + 1234)

# ═══════════════════════════════════════════════════════════════════════════
# QEMU Machine Configuration
# ═══════════════════════════════════════════════════════════════════════════
QEMU_MACHINE  = -machine virt -cpu cortex-a72

# Kernel & rootfs
QEMU_BOOT     = -kernel $(KERNEL_IMAGE)
QEMU_BOOT    += -drive file=$(ROOTFS_IMG),format=raw,if=virtio

# Kernel command line: serial console + kernel DHCP
QEMU_APPEND   = root=/dev/vda rw console=ttyAMA0 ip=dhcp

# Hardware resources
QEMU_HW       = -smp $(CPUS) -m $(MEM)

# Serial & GDB
QEMU_SERIAL   = -serial mon:stdio -gdb tcp::$(GDBPORT)

# Networking: user-mode with SSH port forwarding
QEMU_NET      = -netdev user,id=net0,hostfwd=tcp::$(SSH_PORT)-:22
QEMU_NET     += -device virtio-net-pci,netdev=net0

# 9p host share: mount tag = "hostshare", mapped in guest as /mnt/host
QEMU_9P       = -fsdev local,id=host_share,path=$(SHARE_DIR),security_model=mapped-xattr
QEMU_9P      += -device virtio-9p-pci,fsdev=host_share,mount_tag=hostshare

# Compose full QEMU option set
QEMUOPTS      = $(QEMU_MACHINE) $(QEMU_HW) $(QEMU_SERIAL)
QEMUOPTS     += $(QEMU_BOOT) -append "$(QEMU_APPEND)"
QEMUOPTS     += $(QEMU_NET) $(QEMU_9P)
QEMUOPTS     += $(QEMUEXTRA)

# ═══════════════════════════════════════════════════════════════════════════
# Phony Targets
# ═══════════════════════════════════════════════════════════════════════════
.PHONY: help all kernel build-rootfs qemu qemu-persist qemu-gdb \
        gdb ssh pre-qemu clean clean-cache clean-all print-qemu print-gdbport

.DEFAULT_GOAL := help

# ═══════════════════════════════════════════════════════════════════════════
# Help
# ═══════════════════════════════════════════════════════════════════════════
help:
	@echo ""
	@echo "  QEMU AArch64 Dev Environment"
	@echo "  ════════════════════════════════════════════════"
	@echo ""
	@echo "  Kernel:"
	@echo "    make kernel             Build minimal kernel with scripts/kernel.config"
	@echo ""
	@echo "  Rootfs:"
	@echo "    make build-rootfs       Build rootfs (cached debootstrap, sudo)"
	@echo ""
	@echo "  QEMU:"
	@echo "    make qemu               Stateless launch (-snapshot)"
	@echo "    make qemu-persist       Persistent launch (writes to image)"
	@echo "    make qemu-gdb           Launch paused, waiting for GDB"
	@echo "    make ssh                SSH into running VM (port $(SSH_PORT))"
	@echo "    make gdb                Attach GDB to QEMU"
	@echo ""
	@echo "  Utility:"
	@echo "    make all                Build everything (kernel + rootfs)"
	@echo "    make clean-cache        Remove debootstrap cache (force full rebuild)"
	@echo "    make clean-all          Remove all artifacts including cache"
	@echo "    make clean              Remove build artifacts"
	@echo "    make print-qemu         Print QEMU binary path"
	@echo "    make print-gdbport      Print GDB port"
	@echo ""
	@echo "  Tunables (override via env or command line):"
	@echo "    CPUS=$(CPUS)  MEM=$(MEM)  SSH_PORT=$(SSH_PORT)"
	@echo "    ROOTFS_SIZE=$(ROOTFS_SIZE)MB  KERNEL_JOBS=$(KERNEL_JOBS)"
	@echo ""
	@echo "  9p Workflow:"
	@echo "    Host: place files in ./$(SHARE_DIR)/"
	@echo "    Guest: access them at /mnt/host/"
	@echo ""
	@echo "  Stateless Tip:"
	@echo "    VM runs with -snapshot. To persist changes:"
	@echo "    Ctrl-A c → (qemu) commit all"
	@echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Build All
# ═══════════════════════════════════════════════════════════════════════════
all: kernel build-rootfs

# ═══════════════════════════════════════════════════════════════════════════
# Kernel Targets
# ═══════════════════════════════════════════════════════════════════════════

# Build from allnoconfig and import only the requested QEMU/debug features.
kernel: $(KERNEL_CONFIG)
	@echo "==> Generating minimal arm64 config"
	cd $(KERNEL_DIR) && ARCH=arm64 CROSS_COMPILE=$(GCCPREFIX) \
		./scripts/kconfig/merge_config.sh -n /dev/null ../$(KERNEL_CONFIG)
	@set -e; \
	for option in VIRTIO_PCI VIRTIO_BLK VIRTIO_NET NET_9P_VIRTIO \
			9P_FS EXT4_FS SERIAL_AMBA_PL011_CONSOLE IP_PNP_DHCP \
			BPF_SYSCALL DEBUG_INFO_BTF GDB_SCRIPTS; do \
		state=`$(KERNEL_DIR)/scripts/config --file $(KERNEL_DIR)/.config --state $$option`; \
		test "$$state" = y || { echo "ERROR: Required CONFIG_$$option resolved to $$state"; exit 1; }; \
	done
	@echo "==> Config stats: $$(grep -c '=y' $(KERNEL_DIR)/.config) built-in, $$(grep -c '=m' $(KERNEL_DIR)/.config) modules"
	@echo "==> Building kernel Image (jobs=$(KERNEL_JOBS))"
	$(MAKE) -C $(KERNEL_DIR) ARCH=arm64 CROSS_COMPILE=$(GCCPREFIX) \
		Image -j$(KERNEL_JOBS)

# ═══════════════════════════════════════════════════════════════════════════
# Rootfs Target
# ═══════════════════════════════════════════════════════════════════════════
build-rootfs: $(ROOTFS_IMG)

$(ROOTFS_IMG): $(SCRIPTS_DIR)/build-rootfs.sh
	@echo "==> Building rootfs (requires sudo)"
	@mkdir -p $(OBJDIR) $(SHARE_DIR)
	sudo $(SCRIPTS_DIR)/build-rootfs.sh $(ROOTFS_IMG) $(ROOTFS_SIZE)

# ═══════════════════════════════════════════════════════════════════════════
# GDB Setup
# ═══════════════════════════════════════════════════════════════════════════
.gdbinit: .gdbinit.tmpl
	sed "s/localhost:1234/localhost:$(GDBPORT)/" < $^ > $@

gdb: .gdbinit
	$(GDB) -x .gdbinit

# ═══════════════════════════════════════════════════════════════════════════
# QEMU Targets
# ═══════════════════════════════════════════════════════════════════════════

# Pre-flight checks
pre-qemu: .gdbinit
	@test -f $(KERNEL_IMAGE) || { echo "ERROR: Kernel Image not found. Run 'make kernel' first."; exit 1; }
	@test -f $(ROOTFS_IMG)   || { echo "ERROR: Rootfs image not found. Run 'make build-rootfs' first."; exit 1; }
	@test -d $(SHARE_DIR)    || mkdir -p $(SHARE_DIR)
	@rm -f qemu.pcap

# Stateless launch (default): -snapshot ensures all writes are discarded on exit
# To persist changes: Ctrl-A c → (qemu) commit all
qemu: pre-qemu
	@echo "***"
	@echo "*** Stateless mode (-snapshot). Changes are discarded on exit."
	@echo "*** To persist: Ctrl-A c → commit all"
	@echo "*** SSH: ssh -p $(SSH_PORT) root@localhost  (password: root)"
	@echo "*** Use Ctrl-A x to exit QEMU"
	@echo "***"
	$(QEMU) -nographic $(QEMUOPTS) -snapshot

# Persistent launch: writes go directly to the rootfs image
qemu-persist: pre-qemu
	@echo "***"
	@echo "*** Persistent mode. Changes are written to $(ROOTFS_IMG)."
	@echo "*** SSH: ssh -p $(SSH_PORT) root@localhost  (password: root)"
	@echo "*** Use Ctrl-A x to exit QEMU"
	@echo "***"
	$(QEMU) -nographic $(QEMUOPTS)

# Debug launch: paused at boot, waiting for GDB connection
qemu-gdb: pre-qemu
	@echo "***"
	@echo "*** Paused. Attach GDB with: make gdb"
	@echo "*** GDB port: $(GDBPORT)"
	@echo "***"
	$(QEMU) -nographic $(QEMUOPTS) -snapshot -S

# SSH into the running VM
ssh:
	@echo "==> Connecting to VM via SSH (port $(SSH_PORT))..."
	ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
		-p $(SSH_PORT) root@localhost

# ═══════════════════════════════════════════════════════════════════════════
# Utility Targets
# ═══════════════════════════════════════════════════════════════════════════
print-qemu:
	@echo $(QEMU)

print-gdbport:
	@echo $(GDBPORT)

clean:
	rm -f .gdbinit qemu.pcap
	rm -f $(ROOTFS_IMG)
	@echo "Note: Debootstrap cache preserved. Use 'make clean-cache' to remove it."
	@echo "Note: Kernel build artifacts not cleaned. Use 'make -C $(KERNEL_DIR) mrproper' manually."

clean-cache:
	rm -f $(OBJDIR)/rootfs-base.tar
	@echo "Debootstrap cache removed. Next 'make build-rootfs' will run full debootstrap."

clean-all: clean clean-cache
	rm -rf $(OBJDIR)
