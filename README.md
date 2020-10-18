# WD My Cloud Gen2 aka wdmc-gen2 based on Marvell ARMADA 375 ##

* mainline kernel support
	tested with 4.18.x / 5.6.x / 5.8.x
	- device tree source
		armada-375-wdmc-gen2.dts
	- kernel config
		kernel-4.18.19.config, kernel-5.6.config kernel-5.8.16.config kernel-default.config
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

* general install instructions

	To use the prebuilt releases on your wdmc you'll have to decide wether to use a USB drive or the internal drive. 
	
	##### USB:

	create a FAT32 partition (this will be used to boot, will be called sdb1)
	create a ext4 partition (this will be used as root, will be called sdb2)
	create a folder called 'boot' on sdb1
	move the files from release/boot into the boot folder on sdb1. Rename/link the uImage-5.6 file to uImage. Make sure both the uImage and uRamdisk are executable
	extract the buster-rootfs.tar.gz on the sdb2 partition
	copy the release/lib/ folder onto the sdb2 partition (to add the 5.6 modules)
	adjust sdb2/etc/fstab to fit your needs (will probably be ok)
	boot wdmc with usb stick, root password is '1234', configure/add packages as needed
	
	##### Internal:

	create ext4 partition (this should be the third, so /dev/sda3)
	copy the folder from release/boot into sda3. Rename/link the uImage-5.6 file to uImage. Make sure both the uImage and uRamdisk are executable
	extract the buster-rootfs.tar.gz on the sda3 partition
	copy the release/lib/ folder onto the sda3 partition (to add the 5.6 modules)
	adjust sda3/etc/fstab to fit your needs (you don't need seperate root / boot folders, so adjust this)
	boot wdmc, root password is '1234', configure/add packages as needed
	I suggest starting with USB stick, because this requires no changes on the internal harddisk.

	If you need custom initramfs or different kernel settings, check the code and build neccessary files yourself.
		
Thanks to AllesterFox (http://anionix.ddns.net/WDMyCloud/WDMyCloud-Gen2/) and https://github.com/Johns-Q/wdmc-gen2
