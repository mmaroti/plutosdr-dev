# plutosdr-dev

<img align="right" width="200" src="https://wiki.analog.com/_media/university/tools/pluto/pluto_in_hand.png">

This repository allows you to modify the [ADALM-PLUTO](https://wiki.analog.com/university/tools/pluto) 
firmware without changing the submodules of the Analog Devices [plutosdr-fw](https://github.com/analogdevicesinc/plutosdr-fw.git)
repository. The build script is completely rewritten and made faster with the following features:

* The FPGA code can be modified and built in the plutosdr-dev directory.
* The linux, buildroot, hdl and u-boot are built in the plutosdr-fw directory.
* All build artifacts are stored in a build directory.
* The FPGA project can be modified and compiled with the Vivado GUI.
* You can run `make linux-menuconfig` or `make buildroot-menuconfig` to configure your environment.

## Usage

```
git clone https://github.com/analogdevicesinc/plutosdr-fw.git --recurse-submodules
git clone https://github.com/mmaroti/plutosdr-dev.git
cd plutosdr-dev
export PLUTOSDR_FW=../plutosdr-fw
source /opt/Xilinx/Vivado/2019.1/settings64.sh
make
```

The code is released under its original license. It was tested on plutosdr-fw version v0.33 (8af5c0ad) with Vivado 2019.1.

## Links

* https://wiki.analog.com/university/tools/pluto
* https://gitlab.com/librespacefoundation/sdrmakerspace/radtest/-/wikis/ADALM-Pluto-sdr

## Issues

* If you encounter the
`WARNING: [Vivado 12-508] No pins matched 'get_pins -hierarchical -filter {NAME =~ *i_rx_data_iddr/C || NAME =~ *i_rx_data_iddr/D}'`, then you have probably deleted the untracked git file `plutosrd-fw/hdl/library/axi_ad9361/bd/bd.tcl` making the repository dirty. This file is generated and should have been listed in their `.gitignore`. Just clean the `axi_ad9361` library with `make clean` in that folder and it will be regenerated.

* Currently only the `pluto.dfu` is generated and the bootloaders are not. You do not need to touch the bootloaders, or just use the original repository. I am not responsible for the use of this library if you 
damage your Pluto. I recommend to program your Pluto with the `make dfu-ram` command. Just unplug it afterwards and it will be restored to its original firmware.

* The `rootfs.cpio.gz` is always rebuilt if you create a new commit. This is intended, as the git versions are
embedded in the firmware. After logging in, you can view all git versions with `cat /opt/VERSIONS`.
