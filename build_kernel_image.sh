#!/bin/bash

# Required gcc:
#armada370-gcc464_glibc215_hard_armada-GPL.txz (included in git)
#gcc-arm-none-eabi (downloadable via apt)

KERNEL_VERSION='5.6'

# we can never know what aliases may be set, so remove them all
unalias -a

# do preparation steps

# generate output directory
mkdir -p output/boot

if [ ! -d linux-$KERNEL_VERSION ]; then
    # git clone linux tree
    git clone --branch "v$KERNEL_VERSION" --depth 1 https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git

    # rename directory
    mv linux-stable linux-$KERNEL_VERSION
fi

# copy config and dts

if [ ! -f kernel-$KERNEL_VERSION.config ]; then
    cp kernel-default.config kernel-$KERNEL_VERSION.config
fi

cp kernel-$KERNEL_VERSION.config linux-$KERNEL_VERSION/.config
cp armada-375-wdmc-gen2.dts linux-$KERNEL_VERSION/arch/arm/boot/dts/


# cd into linux source
cd linux-$KERNEL_VERSION

#makehelp='make CROSS_COMPILE=/opt/arm-marvell-linux-gnueabi/bin/arm-marvell-linux-gnueabi- ARCH=arm'
makehelp='make CROSS_COMPILE=/usr/bin/arm-none-eabi- ARCH=arm'

$makehelp menuconfig
$makehelp -j2 zImage
$makehelp armada-375-wdmc-gen2.dtb
cat arch/arm/boot/zImage arch/arm/boot/dts/armada-375-wdmc-gen2.dtb > zImage_and_dtb
mkimage -A arm -O linux -T kernel -C none -a 0x00008000 -e 0x00008000 -n 'WDMC-Gen2' -d zImage_and_dtb ../output/boot/uImage-$KERNEL_VERSION
rm zImage_and_dtb

$makehelp modules
$makehelp INSTALL_MOD_PATH=../output modules_install

cd ..

cp uRamdisk output/boot/

#rm output/lib/modules/$KERNEL_VERSION/source
#rm output/lib/modules/$KERNEL_VERSION/build

chmod =rwxrxrx output/boot/uRamdisk
chmod =rwxrxrx output/boot/uImage-$KERNEL_VERSION


