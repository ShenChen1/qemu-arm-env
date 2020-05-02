echo + target remote localhost:25000\n
target remote localhost:25000

# If this fails, it's probably because your GDB doesn't support ELF.
# Look at the tools page at
# for instructions on building GDB with ELF support.
echo + symbol-file ./linux-4.3-comment/vmlinux\n
symbol-file ./linux-4.3-comment/vmlinux

set pagination off
