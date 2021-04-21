
ifeq (, $(wildcard $(PLUTOSDR_FW)))
$(error Please set PLUTOSDR_FW to your plutosdr-fw directory)
else
PLUTOSDR_FW := $(abspath $(PLUTOSDR_FW))
$(info PLUTOSDR_FW is $(PLUTOSDR_FW))
endif

ifeq (, $(shell which vivado))
$(error Could not find vivado, please run settings.sh)
else
$(info VIVADO is $(shell which vivado))
endif

CROSS_COMPILE ?= arm-linux-gnueabihf-

ifeq (, $(shell which $(CROSS_COMPILE)gcc))
$(error Could not find $(CROSS_COMPILE)gcc cross compiler)
else
$(info CROSS_COMPILE is $(CROSS_COMPILE))
endif

NCORES = $(shell nproc)
DEVICE_VID := 0x0456
DEVICE_PID := 0xb673

all: build/pluto.dfu

clean:
	rm -rf build

clean-all: clean
	$(MAKE) -C $(PLUTOSDR_FW) clean
	cd $(PLUTOSDR_FW)/linux && git clean -fx
	cd $(PLUTOSDR_FW)/buildroot && git clean -fx
	cd $(PLUTOSDR_FW)/hdl && git clean -fx
	cd $(PLUTOSDR_FW)/u-boot-xlnx && git clean -fx

.PHONY: all clean dfu-ram linux-menuconfig build-menuconfig FORCE

FORCE:

build:
	mkdir -p build

# vivado

PLUTO_LIBS := axi_ad9361 axi_dmac util_pack/util_cpack2 util_pack/util_upack2
PLUTO_FILES := system_project.tcl system_bd.tcl system_top.v system_constr.xdc

$(PLUTOSDR_FW)/hdl/library/%/component.xml:
	$(MAKE) -C $(dir $@) -j1 xilinx

build/pluto.runs/impl_1/system_top.sysdef: $(PLUTO_FILES) $(foreach lib,$(PLUTO_LIBS),$(PLUTOSDR_FW)/hdl/library/$(lib)/component.xml) | build
	cp -fa $(PLUTO_FILES) build
	cd build && vivado -mode batch -source system_project.tcl

build/system_top.bit: build/pluto.runs/impl_1/system_top.sysdef
	unzip -o build/pluto.runs/impl_1/system_top.sysdef system_top.bit -d build
	touch build/system_top.bit

build/sdk/fsbl/Release/fsbl.elf: build/pluto.runs/impl_1/system_top.sysdef
	cp -fa build/pluto.runs/impl_1/system_top.sysdef build/system_top.hdf
	cp -fa build/pluto.srcs/sources_1/bd/system/ip/system_sys_ps7_0/ps7_init* build
	rm -rf build/sdk
	xsdk -batch -source $(PLUTOSDR_FW)/scripts/create_fsbl_project.tcl

build/fsbl.elf: build/sdk/fsbl/Release/fsbl.elf
	cp -fa $< $@ 

# linux

$(PLUTOSDR_FW)/linux/.config:
	$(MAKE) -C $(PLUTOSDR_FW)/linux ARCH=arm zynq_pluto_defconfig

linux-menuconfig:
	$(MAKE) -C $(PLUTOSDR_FW)/linux ARCH=arm menuconfig

$(PLUTOSDR_FW)/linux/arch/arm/boot/zImage: $(PLUTOSDR_FW)/linux/.config
	$(MAKE) -C $(PLUTOSDR_FW)/linux -j $(NCORES) ARCH=arm CROSS_COMPILE=$(CROSS_COMPILE) zImage UIMAGE_LOADADDR=0x8000

build/zImage: $(PLUTOSDR_FW)/linux/arch/arm/boot/zImage | build
	cp -fa $< $@

DTC_CPP_FLAGS := -x assembler-with-cpp -nostdinc \
                 -I $(PLUTOSDR_FW)/linux/include \
                 -I $(PLUTOSDR_FW)/linux/arch/arm/boot/dts \
                 -undef -D__DTS__

build/%.dtb: %.dts zynq-pluto-sdr.dtsi | build
	cpp -I $(dir $<) $(DTC_CPP_FLAGS) < $< | dtc -I dts -O dtb -o $@

# buildroot

VERSION_OLD = $(shell test -f build/VERSIONS && head -n 1 build/VERSIONS)
VERSION_NEW = device-fw plutosdr-dev-$(shell git describe --dirty --always --tags)

build/VERSIONS: FORCE | build
ifneq ($(VERSION_OLD), $(VERSION_NEW))
	echo $(VERSION_NEW) > $@
	echo plutosdr-fw $(shell cd $(PLUTOSDR_FW) && git describe --dirty --always --tags) >> $@
	echo hdl $(shell cd $(PLUTOSDR_FW)/hdl && git describe --dirty --always --tags) >> $@
	echo buildroot $(shell cd $(PLUTOSDR_FW)/buildroot && git describe --dirty --always --tags --first-parent) >> $@
	echo linux $(shell cd $(PLUTOSDR_FW)/linux && git describe --dirty --always --tags --first-parent) >> $@
	echo u-boot-xlnx $(shell cd $(PLUTOSDR_FW)/u-boot-xlnx && git describe --dirty --always --tags) >> $@
endif

$(PLUTOSDR_FW)/buildroot/.config:
	$(MAKE) -C $(PLUTOSDR_FW)/buildroot ARCH=arm zynq_pluto_defconfig

buildroot-menuconfig:
	$(MAKE) -C $(PLUTOSDR_FW)/buildroot ARCH=arm menuconfig

$(PLUTOSDR_FW)/buildroot/board/pluto/msd/LICENSE.html: $(PLUTOSDR_FW)/buildroot/.config
	echo "<!DOCTYPE html><html><head>" > $@
	echo "<meta http-equiv='refresh' content='1;url=https://wiki.analog.com/university/tools/pluto'/>" >> $@
	echo "</head></html>" >> $@

$(PLUTOSDR_FW)/buildroot/output/images/rootfs.cpio.gz: $(PLUTOSDR_FW)/buildroot/.config $(PLUTOSDR_FW)/buildroot/board/pluto/msd/LICENSE.html build/VERSIONS
	cp -fa build/VERSIONS $(PLUTOSDR_FW)/buildroot/board/pluto/VERSIONS
	$(MAKE) -C $(PLUTOSDR_FW)/buildroot -j $(NCORES) ARCH=arm CROSS_COMPILE=$(CROSS_COMPILE) BUSYBOX_CONFIG_FILE=$(PLUTOSDR_FW)/buildroot/board/pluto/busybox-1.25.0.config all

build/rootfs.cpio.gz: $(PLUTOSDR_FW)/buildroot/output/images/rootfs.cpio.gz | build
	cp -fa $< $@

# pluto.dfu

$(PLUTOSDR_FW)/u-boot-xlnx/tools/mkimage:
	$(MAKE) -C $(PLUTOSDR_FW)/u-boot-xlnx ARCH=arm zynq_pluto_defconfig
	$(MAKE) -C $(PLUTOSDR_FW)/u-boot-xlnx -j $(NCORES) ARCH=arm CROSS_COMPILE=$(CROSS_COMPILE)

build/pluto.its: $(PLUTOSDR_FW)/scripts/pluto.its | build
	cp -fa $< $@

build/pluto.itb: $(PLUTOSDR_FW)/u-boot-xlnx/tools/mkimage build/pluto.its build/zImage build/rootfs.cpio.gz build/system_top.bit build/zynq-pluto-sdr.dtb build/zynq-pluto-sdr-revb.dtb build/zynq-pluto-sdr-revc.dtb
	cd build && $(PLUTOSDR_FW)/u-boot-xlnx/tools/mkimage -f pluto.its pluto.itb

build/pluto.frm: build/pluto.itb
	md5sum $< | cut -d ' ' -f 1 > $@.md5
	cat $< $@.md5 > $@

build/pluto.dfu: build/pluto.itb
	cp $< $<.tmp
	dfu-suffix -a $<.tmp -v $(DEVICE_VID) -p $(DEVICE_PID)
	mv $<.tmp $@
	@echo "*** DONE, please run make dfu-ram to program ***"

# programming

dfu-ram: build/pluto.dfu
	sshpass -p analog ssh root@pluto '/usr/sbin/device_reboot ram;'
	sleep 6
	dfu-util -D build/pluto.dfu -a firmware.dfu
	dfu-util -e -a firmware.dfu
