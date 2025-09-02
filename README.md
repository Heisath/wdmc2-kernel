# build tools for wdmc-gen2

## WD My Cloud Gen2 based on Marvell ARMADA 375

[![Donate](https://img.shields.io/badge/Donate-PayPal-green.svg)](https://www.paypal.com/donate?hosted_button_id=HXWRU82YBV7HC&source=url)

This repository contains documentation and sources to build your own linux kernel, ramdisk and debian to run a WD MyCloud Gen2 drive. It can also be used as a starting point, to get similar devices running or just learn about linux booting in general.

### Whats included?

* everything to run a mainline kernel and debian
  * device tree source ./dts/armada-375-wdmc-gen2.dts
  * kernel config for various kernels (check ./config/)
  * some tweaks and pointers in txt files ./docs/
  * toolchain for building old kernels is included as txz ./toolchain/ . I suggest using the gcc-arm-none-eabi toolchain via apt!
  * a build script to build the kernel, ramdisk and debootstrap a debian system
  * some fixes/customization for the device
  * a script to update the ramdisk in place

### How to use?

* clone repository, run build.sh, select the options you want, deploy to wdmc2.

* prerequisites for building will be installed by build.sh automatically.
  * buildscript has been developed and tested on Ubuntu Jammy with gcc-arm-none-eabi hosted in a VirtualBox, there are known problems when using older debian/ubuntu releases or wsl(2)
  * `apt-get install build-essential bc libncurses5 dialog u-boot-tools git libncurses-dev lib32z1 lib32ncurses5-dev libmpc-dev libmpfr-dev libgmp3-dev flex bison debootstrap debian-archive-keyring qemu-user-static`
  * gcc for arm eabi `apt-get install gcc-arm-none-eabi`
    * OR (ONLY USE IF ABOVE DOES NOT WORK)
    * extract the gcc/glibc archive from toolchain to /opt
    * adjust the path to the gcc in build.sh

* build.sh
  * provides a way of building a kernel, rootfs and uRamdisk
  * run build.sh as root (or with sudo)
  * script will use dialog to ask for features and configuration
  * possible parameters to skip dialogs are:
    * `--kernel` to select kernel building:
    * `--kernelbranch {branch}` to select kernel branch from kernel.org
    * `--clean` to reset and fetch git before compiling kernel (to remove possible changes)
    * `--config` to use menuconfig to allow user to customize kernel
    * `--rootfs` to select rootfs creation:
    * `--release {debianrelease}` to select the debian release to use as rootfs
      * `--changes` to pause and wait for changes in the rootfs before unmounting and packaging (this allows you to do customization)
    * `--initramfs` to create new initramfs in rootfs
    * `--root-pw {rootpw}` to select root pw for new rootfs
    * `--hostname {host}` to select hostname for new rootfs
    * `--zram` to enable logging and swap via ZRAM
    * `--boot {usb/hdd}` to select fstab to use (either for booting from usb or hdd)
  * if a parameters is not given, the default value is used or the user is prompted
  * if building a rootfs build.sh will include the tweaks from ./tweaks/  You can adjust fstab and various other stuff there, files will be copied straight to rootfs
  * depending on the selected actions the script will:
    * for the kernel:
      * git clone and checkout the kernel
      * insert kernel-config and device tree into kernel
      * try making it with menuconfig
      * attach dtb to zImage then mkimage
      * place the results in ./output/boot and ./output/modules
    * for the rootfs:
      * use debootstrap to generate a debian rootfs in ./output/rootfs/
      * apply the tweaks and setup some useful programs via apt
      * copy the results from kernel making into the right folders (boot and lib)
      * if building initramfs is enabled it will also:
        * run build_initramfs.sh in the chroot and generate a new uRamdisk
      * pack the rootfs into a tar.gz so you can easily extract it on your usb/hdd

* build_initramfs.sh
  * this script builds a minimal initramfs
  * can either be run on the wdmc directly and put the output into /boot
  * can be used in a chroot to precompile uRamdisk. This is how it is used by build.sh
  * the generated uRamdisk can boot from kernel commandline, usb-stick 2nd partition, hdd 3rd partition

### How to install?

To use the prebuilt releases on your wdmc you'll have to decide wether to use a USB drive or the internal drive.

#### USB (USB 2.0 stick is recommended, USB 3.0 does have troubles rebooting)

* create a FAT32 partition (this will be used to boot, sdb1 - 200MB)
* create a ext4 partition (this will be used as root, sdb2 - 1GB+)
* extract boot-5.x.x.tar.gz on sdb1 (FAT32) partition
* extract the {release}-rootfs.tar.gz on the sdb2 (ext4) partition
* adjust sdb2/etc/fstab to fit your needs (will probably be ok)
* boot wdmc with usb stick, root password is '1234'
* adjust time and date, use `hwclock --systohc` to update RTC
* configure/add packages as needed

#### Internal

* make sure drive is using gpt
* create root ext4 partition as sda3
  * in original wd firmare this needed to be /dev/sda3 (as sda1 was swap and sda2 data)
  * new uRamdisk also supports booting from /dev/sda1 (though this is untested and might not work)
* extract {release}-rootfs.tar.gz on the root
* adjust sda3/etc/fstab to fit your needs (check it at least!)
* boot wdmc, root password is '1234' configure/add packages as needed
* adjust time and date, use `hwclock --systohc` to update RTC
* configure/add packages as needed
* I suggest starting with USB stick, because this requires no changes on the internal hard disk.

If you need custom initramfs or different kernel settings, check the code and build necessary files yourself.

### How is the WDMC booting?

This section describes the boot process of the wdmc, it might help understand why the above steps are necessary or how the booting works.

#### u-boot stage

1. u-boot (on internal flash) is loaded, starts execution and hardware initialization
2. looks for proper boot media. It checks:

* first partition on usb
* third partition on sata
* network TFTP

3. if on the above locations a folder call `boot` is found, it tries to load

* uImage
* uRamdisk

4. afterwards execution is passed to the linux kernel in uImage
5. kernels loads, initializes the system further, then passes control to the uRamdisk.

##### uRamdisk stage

6. the uRamdisk contains busybox a small shell. This is used to set up a basic linux system containing /dev/ /proc/ /sys/
7. tries to mount the full debian root, therefore it tries to mount the following destinations

* whatever is passed to the kernel as "root"
* /dev/sdb2 (so second partition on usb)
* /dev/sda1 (so first partition on sata)
* /dev/sda3 (so third partition on sata)

8. if no suitable root is found, it hands control to the user via a rescue shell
9. if a mount was successful, it sets up the led triggers, mac address and runs switch_root to load the real system

##### debian stage

10. debian starts.

### How to debug?

If you get stuck at any point it is really helpful to access the boot log and watch uboot and the uRamdisk do its stuff. You can connect a 3.3V usb-serial converter (also often referred to as FTDI Breakout or USB2UART) to the UART pins on the wdmc. The wdmc is using 115200b8n1 with 3.3V pullups on the data lines. Use the image below for reference (also check the docs folder!)
![image](https://github.com/Heisath/wdmc2-kernel/blob/master/docs/UART_Pinout.jpg)

### Thanks to

AllesterFox (<http://anionix.ddns.net/WDMyCloud/WDMyCloud-Gen2/>) \
Johns Q <https://github.com/Johns-Q/wdmc-gen2> for their original work on the wdmc-gen2 \
ARMBIAN (<https://github.com/armbian/build>) for their awesome build script which gave lots of inspiration and the zram config :)
