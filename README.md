# wdmc-gen2
WD My Cloud Gen2 kernel build script


## WD My Cloud Gen2 aka wdmc-gen2 based on Marvell ARMADA 375 ##

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

	- build-initramfs.sh

		builds a minimal initramfs.  Can boot from kernel commandline,
		usb-stick 2nd partition, hdd 3rd partition.
		needs to be placed in /boot/uRamdisk.

        This needs to be run on the wdmycloud. So to get your first boot use the uRamdisk provided!
		
Thanks to AllesterFox (http://anionix.ddns.net/WDMyCloud/WDMyCloud-Gen2/) and https://github.com/Johns-Q/wdmc-gen2
