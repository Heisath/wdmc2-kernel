# build tools for wdmc-gen2
## WD My Cloud Gen2 based on Marvell ARMADA 375

[![Donate](https://img.shields.io/badge/Donate-PayPal-green.svg)](https://www.paypal.com/donate?hosted_button_id=HXWRU82YBV7HC&source=url)

* mainline kernel support
	tested with 4.18.x / 5.10.x / 5.11.x
	- device tree source ./dts/armada-375-wdmc-gen2.dts
	- kernel config for various kernels included check ./config/
	- some tweaks and pointers in txt files ./docs/
	- toolchain for building old kernels is included as txz ./toolchain/ . I suggest using the gcc-arm-none-eabi toolchain via apt!
	- supports caching of kernel and rootfs so not everything needs to be rebuilt everytime
	- built rootfs has zram support and uses it for swap and logging
	
* prerequisites for building 
	- `apt-get install build-essential bc libncurses5 u-boot-tools git libncurses-dev lib32z1 lib32ncurses5-dev libmpc-dev libmpfr-dev libgmp3-dev flex bison debootstrap debian-archive-keyring qemu-user-static`
	- gcc for arm eabi `apt-get install gcc-arm-none-eabi`
		- OR (ONLY USE IF ABOVE DOES NOT WORK)
		- extract the gcc/glibc archive to /opt
		- adjust the path to the gcc in build.sh

* build.sh
	- provides a way of building a kernel, rootfs and uRamdisk
	- run build.sh as root (or with sudo)
	- possible parameters are:
		- `--release {debianrelease}` to select the debian release to use as rootfs
		- `--root-pw {rootpw}` to select root pw for new rootfs
		- `--hostname {host}` to select hostname for new rootfs
		- `--kernel {version}` to select kernel version to build
		- `--kernelonly` to only build the kernel (without uRamdisk and rootfs)
		- `--rootonly` to only build the rootfs (without kernel and uRamdisk)
		- `--nokernel` to only build the rootfs + uRamdisk
		- `--noinitramfs` to build kernel and rootfs without uRamdisk
		- `--changes` to pause and wait for changes in the rootfs before unmounting and packaging (this allows you to do customization)
		- `--noclean` to compile kernel without resetting and fetching git
		- `--noconfig` to skip menuconfig part of kernel
		- if a parameters is not given, the default value is used. Check in build.sh for default and other usage
	- if building a rootfs build.sh will include the tweaks from ./tweaks/  You can adjust fstab and various other stuff there
	
	- Depending on the selected actions the script will:
		- for the kernel: 
			- git clone and checkout the kernel 
			- insert kernel-config and device tree into kernel
			- try making it with menuconfig 
			- attach dtb to zImage then mkimage
			- place the results in ./output/boot and ./output/modules
		- for the rootfs:
			- use debootstrap to generate a debian rootfs in ./output/rootfs/
			- apply the tweaks and setup some useful programs via apt
			- copy the results from kernel making into the right folders (boot and lib)
			- if building initramfs is enabled it will also:
				- run build_initramfs.sh in the chroot and generate a new uRamdisk 
			- pack the rootfs into a tar.gz so you can easily extract it on your usb/hdd
			
* build_initramfs.sh
		
	builds a minimal initramfs.  Can boot from kernel commandline,
	usb-stick 2nd partition, hdd 3rd partition.
	needs to be placed in /boot/uRamdisk.

       	This needs to be run on the wdmycloud. So to get your first boot use the uRamdisk provided!
	Or use the build.sh and also create a rootfs on your host to chroot and run this in.
		

* general install instructions

	To use the prebuilt releases on your wdmc you'll have to decide wether to use a USB drive or the internal drive. 
	
	##### USB:

	- create a FAT32 partition (this will be used to boot, will be called sdb1)
	- create a ext4 partition (this will be used as root, will be called sdb2)
	- create a folder called 'boot' on sdb1
	- move the files from release/boot into the boot folder on sdb1. Rename/link the uImage-5.6 file to uImage. Make sure both the uImage and uRamdisk are executable
	- extract the buster-rootfs.tar.gz on the sdb2 partition
	- copy the release/lib/ folder onto the sdb2 partition (to add the 5.6 modules)
	- adjust sdb2/etc/fstab to fit your needs (will probably be ok)
	- boot wdmc with usb stick, root password is '1234', configure/add packages as needed
	
	##### Internal:

	- create ext4 partition (this should be the third, so /dev/sda3)
	- copy the folder from release/boot into sda3. Rename/link the uImage-5.6 file to uImage. Make sure both the uImage and uRamdisk are executable
	- extract the buster-rootfs.tar.gz on the sda3 partition
	- copy the release/lib/ folder onto the sda3 partition (to add the 5.6 modules)
	- adjust sda3/etc/fstab to fit your needs (you don't need seperate root / boot folders, so adjust this)
	- boot wdmc, root password is '1234', configure/add packages as needed
	- I suggest starting with USB stick, because this requires no changes on the internal harddisk.

	If you need custom initramfs or different kernel settings, check the code and build neccessary files yourself.
		
Thanks to: \
AllesterFox (http://anionix.ddns.net/WDMyCloud/WDMyCloud-Gen2/) \
Johns Q https://github.com/Johns-Q/wdmc-gen2 for their original work on the wdmc-gen2 \
ARMBIAN (https://github.com/armbian/build) for their awesome build script which gave lots of inspiration and the zram config :)
