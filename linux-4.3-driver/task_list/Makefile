ifneq ($(KERNELRELEASE),)
obj-m	:= task_list.o
else
KERNELDIR ?= /lib/modules/$(shell uname -r)/build
KERNELDIR := /opt/development/qemu-project/linux-4.3-comment
PWD       := $(shell pwd)
modules:
	$(MAKE) -C $(KERNELDIR) M=$(PWD)
endif

clean:
	rm -rf *.o *.ko *.mod.c modules.order tmp *.ko.unsigned Module.symvers

