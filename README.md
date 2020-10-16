# WD My Cloud Gen2 aka wdmc-gen2 based on Marvell ARMADA 375 ##

* mainline kernel support
	tested with 4.18.x / 5.6.x
	- device tree source
		armada-375-wdmc-gen2.dts
	- kernel config
		kernel-4.18.19.config, kernel-5.6.config kernel-default.config
	- some tweaks and pointers in txt files
	- build your own kernel
		- required gcc compiler is incuded in case you need it
		- edit build_kernel_image.sh , adjust KERNEL_VERSION to match desired kernel version from kernel.org
		- run build_kernel_image.sh
		- it will:
			- git clone and checkout the kernel 
			- insert kernel-config and device tree into kernel
			- try making it with menuconfig 
			- attach dtb to zImage then mkimage
		- copy uImage to /boot of your boot partition

	- build_initramfs.sh
		
		builds a minimal initramfs.  Can boot from kernel commandline,
		usb-stick 2nd partition, hdd 3rd partition.
		needs to be placed in /boot/uRamdisk.

        	This needs to be run on the wdmycloud. So to get your first boot use the uRamdisk provided!
	- build-debian-rootfs.sh
		
		You can run this script to generate a debian rootfs suitable for the wdmc. Best to run this in some VM (e.g. Ubuntu).
		To change the packages, settings and default root password check in the script. Also change the fstab to your needs (is included in build script).
		
		The script will tar.gz the rootfs so it is easy to copy and extract on the drive for wdmc. Remember to add the kernel and modules!
		
* prerequisites for building 
	- `apt-get install build-essential libncurses5 u-boot-tools git libncurses-dev lib32z1 lib32ncurses5-dev flex bison debootstrap debian-archive-keyring qemu-user-static`
	- gcc for arm eabi (need to adjust build_kernel_image.sh depending on chosen compiler)
		- extract the gcc/glibc archive to /opt
		- OR
		- `apt-get install gcc-arm-none-eabi`

		
Thanks to AllesterFox (http://anionix.ddns.net/WDMyCloud/WDMyCloud-Gen2/) and https://github.com/Johns-Q/wdmc-gen2
