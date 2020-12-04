#!/bin/bash

# Required gcc:
#armada370-gcc464_glibc215_hard_armada-GPL.txz (included in git)    FOR KERNEL VERSION <= 5.6
#gcc-arm-none-eabi (downloadable via apt / included in git)         FOR KERNEL VERSION >= 5.6
#check toolchain subfolder for these

KERNEL_VERSION='5.9.1'

# we can never know what aliases may be set, so remove them all
unalias -a

# do preparation steps
echo "### Cloning linux kernel $KERNEL_VERSION"

# generate output directory
mkdir -p output/boot

if [ ! -d linux-$KERNEL_VERSION ]; then
    # git clone linux tree
    git clone --branch "v$KERNEL_VERSION" --depth 1 https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git

    # rename directory
    mv linux-stable linux-$KERNEL_VERSION
fi

# copy config and dts
echo "### Moving kernel config in place"

if [ ! -f config/kernel-$KERNEL_VERSION.config ]; then
    cp config/kernel-default.config config/kernel-$KERNEL_VERSION.config
fi

cp config/kernel-$KERNEL_VERSION.config linux-$KERNEL_VERSION/.config
cp dts/*.dts linux-$KERNEL_VERSION/arch/arm/boot/dts/


# cd into linux source
cd linux-$KERNEL_VERSION

echo "### Starting make"

#makehelp='make CROSS_COMPILE=/opt/arm-marvell-linux-gnueabi/bin/arm-marvell-linux-gnueabi- ARCH=arm'    FOR KERNEL VERSION <= 5.6
makehelp='make CROSS_COMPILE=/opt/gcc-arm-none-eabi/bin/arm-none-eabi- ARCH=arm'                        #FOR KERNEL VERSION >= 5.6

$makehelp menuconfig
$makehelp -j2 zImage
$makehelp armada-375-wdmc-gen2.dtb
cat arch/arm/boot/zImage arch/arm/boot/dts/armada-375-wdmc-gen2.dtb > zImage_and_dtb
mkimage -A arm -O linux -T kernel -C none -a 0x00008000 -e 0x00008000 -n 'WDMC-Gen2' -d zImage_and_dtb ../output/boot/uImage-$KERNEL_VERSION
rm zImage_and_dtb

$makehelp modules
$makehelp INSTALL_MOD_PATH=../output modules_install

cd ..


echo "### Copying new kernel config to output"
cp linux-$KERNEL_VERSION/.config output/kernel-$KERNEL_VERSION.config

echo "### Adding default ramdisk to output"
cp prebuilt/uRamdisk output/boot/

echo "### Cleanup" 
rm output/lib/modules/*/source
rm output/lib/modules/*/build

chmod =rwxrxrx output/boot/uRamdisk
chmod =rwxrxrx output/boot/uImage-$KERNEL_VERSION


