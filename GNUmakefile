#
# This makefile system follows the structuring conventions
# recommended by Peter Miller in his excellent paper:
#
#	Recursive Make Considered Harmful
#	http://aegis.sourceforge.net/auug97.pdf
#
OBJDIR := obj

# Run 'make V=1' to turn on verbose commands, or 'make V=0' to turn them off.
V ?= 0
ifeq ($(V),1)
override V =
endif
ifeq ($(V),0)
override V = @
endif

# QEMU
QEMU := qemu-system-arm

# GCCPREFIX
GCCPREFIX := arm-cortexa9_neon-linux-gnueabihf-

# try to generate a unique kenerl GDB port
GDBPORT	:= $(shell expr `id -u` % 5000 + 25000)

# try to generate a unique userspace GDB port
DEBUGPORT	:= $(shell expr `id -u` % 5000 + 1234)

# tools
CC	:= $(GCCPREFIX)gcc -pipe
AS	:= $(GCCPREFIX)as
AR	:= $(GCCPREFIX)ar
LD	:= $(GCCPREFIX)ld
OBJCOPY	:= $(GCCPREFIX)objcopy
OBJDUMP	:= $(GCCPREFIX)objdump
NM	:= $(GCCPREFIX)nm
GDB	:= $(GCCPREFIX)gdb

CPUS ?= 4
hostaddr ?= 192.168.0.3
ipaddr ?= 192.168.0.123
gateway ?= 192.168.0.1
netmask ?= 255.255.255.0
netdev ?= eth0

# qemu options
QEMUOPTS = -M vexpress-a9 -smp $(CPUS) -m 256M
QEMUOPTS += -kernel ./linux-4.3-comment/arch/arm/boot/zImage
QEMUOPTS += -dtb ./linux-4.3-comment/arch/arm/boot/dts/vexpress-v2p-ca9.dtb
QEMUOPTS += -drive file=./vexpress.ext3,if=sd,format=raw
QEMUOPTS += -append "noinitrd root=/dev/mmcblk0 init=/linuxrc console=ttyAMA0,115200n8 \
	ip=$(ipaddr):$(bootp):$(gateway):$(netmask):$(netdev):$(netdev):off \
	earlyprintk ignore_loglevel initcall_debug loglevel=8 \
	isolcpus=1-3 nohz_full=1-3 rcu_nocbs=1-3 \
	crashkernel=256M"
QEMUOPTS += -net nic -net tap,id=$(netdev),ifname=tap0,script=no,downscript=no
QEMUOPTS += -serial mon:stdio -gdb tcp::$(GDBPORT)
QEMUOPTS += $(QEMUEXTRA)

.gdbinit: .gdbinit.tmpl
	sed "s/localhost:1234/localhost:$(GDBPORT)/" < $^ > $@

gdb:
	$(GDB) -x .gdbinit

pre-qemu: .gdbinit
#	QEMU doesn't truncate the pcap file.  Work around this.
	@rm -f qemu.pcap

qemu: pre-qemu
	@echo "***"
	@echo "*** Use Ctrl-a x to exit qemu"
	@echo "***"
	$(QEMU) -nographic $(QEMUOPTS)

qemu-gdb: pre-qemu
	@echo "***"
	@echo "*** Now run 'make gdb'." 1>&2
	@echo "***"
	$(QEMU) -nographic $(QEMUOPTS) -S

print-qemu:
	@echo $(QEMU)

print-gdbport:
	@echo $(GDBPORT)

mkmod:
	$(V)mkdir -p module
	$(V)rm -rf module/*.ko
	$(V)find ./linux-4.3-driver/ -name "*.ko" | xargs -i cp '{}' ./module/

mktool:
	$(V)mkdir -p tools
	$(V)find ./linux-4.3-driver/ -name "*.out" | xargs -i cp '{}' ./tools/

mkfs: mkmod mktool
	$(V)dd if=/dev/zero of=vexpress.ext3 bs=1M count=64
	$(V)mkfs.ext3 -F vexpress.ext3
	$(V)mkdir -p tmpfs
	$(V)rm -rf tmpfs/*
	$(V)mount -t ext3 vexpress.ext3 tmpfs -o loop
	$(V)cp -r tools/* tmpfs/
	$(V)cp -r module/* tmpfs/
	$(V)umount tmpfs
	$(V)rm -rf tmpfs
