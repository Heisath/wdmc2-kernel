#!/bin/bash

unalias -a

# Find dir of build.sh and go there
current_dir="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
# check for whitespace in ${current_dir} and exit for safety reasons
grep -q "[[:space:]]" <<<"${current_dir}" && { echo "\"${current_dir}\" contains whitespace. Aborting." >&2 ; exit 1 ; }
cd "${current_dir}" || exit

DIALOG_CANCEL=1
DIALOG_ESC=255
BACKTITLE="WDMC kernel & rootfs build script"

source "${current_dir}"/inc/helpers.sh
source "${current_dir}"/inc/kernel.sh
source "${current_dir}"/inc/rootfs.sh

############################################################
### (SUB) DIRECTORIES TO USE
############################################################
output_dir="${current_dir}/output"
rootfs_dir="${output_dir}/rootfs"
boot_dir="${output_dir}/boot"
cache_dir="${current_dir}/cache"

current_user="$(stat --format %U "${current_dir}"/.git)"

############################################################
### Begin figuring out configuration
############################################################
GHRUNNER='off'
THREADS=8
EXTRA_PKGS='bash-completion htop'
makehelp='make CROSS_COMPILE=/usr/bin/arm-none-eabi- ARCH=arm'                                         #FOR KERNEL VERSION >= 5.6 (via apt)

# start by reading command line arguments
read_arguments "$@"

if [[ "${EUID}" != "0" ]] && [[ $GHRUNNER != 'on' ]]; then
    echo "This script requires root privileges, please rerun using sudo or fakeroot"
    exit 1
fi

if [[ $GHRUNNER != 'on' ]]; then
    echo "### Will try to use apt to install prerequisites."
    apt-get install build-essential bc libncurses5 dialog u-boot-tools git libncurses-dev lib32z1 lib32ncurses5-dev libmpc-dev libmpfr-dev libgmp3-dev flex bison debootstrap debian-archive-keyring qemu-user-static gcc-arm-none-eabi
fi

# calculate dialog sizes
exec 3>&1
dsize=$(dialog --print-maxsize 2>&1 1>&3)
exec 3>&-
dsize=( $(echo "$dsize" | grep -o -E '[0-9]+') )
DIALOG_HEIGHT=$((${dsize[0]} - 12))
DIALOG_WIDTH=$((${dsize[1]} - 8))


# if command line has selected neither kernel nor rootfs we can assume, no selection was done and ask user
if [[ -z $BUILD_KERNEL ]] && [[ -z $BUILD_ROOTFS ]]; then

    # set sensible defaults
    BUILD_KERNEL='on'
    CLEAN_KERNEL_SRC='on'
    ALLOW_KERNEL_CONFIG_CHANGES='off'

    BUILD_ROOTFS='on'
    ALLOW_ROOTFS_CHANGES='off'
    ALLOW_CMDLINE_CHANGES='off'
    ASK_EXTRA_PKGS='off'
    ZRAM_ENABLED='on'

    # Show user checklist to select
    display_checklist "Build setup" "Select components and options for build:" \
        "1" "Linux Kernel" "$BUILD_KERNEL" \
        "2" "Clean Kernel sources" "$CLEAN_KERNEL_SRC" \
        "3" "Allow Kernel config changes" "$ALLOW_KERNEL_CONFIG_CHANGES" \
        "4" "Debian Rootfs" "$BUILD_ROOTFS" \
        "5" "Pause to allow rootfs changes via filesystem" "$ALLOW_ROOTFS_CHANGES" \
        "6" "Enter bash in rootfs for manual changes" "$ALLOW_CMDLINE_CHANGES" \
        "7" "Ask for extra apt pkgs" "$ASK_EXTRA_PKGS" \
        "8" "Enable ZRAM on rootfs" "$ZRAM_ENABLED"

    # Accept user choices
    BUILD_KERNEL='off'
    CLEAN_KERNEL_SRC='off'
    ALLOW_KERNEL_CONFIG_CHANGES='off'
    BUILD_ROOTFS='off'
    ALLOW_ROOTFS_CHANGES='off'
    ALLOW_CMDLINE_CHANGES='off'
    ASK_EXTRA_PKGS='off'
    ZRAM_ENABLED='off'

    [[ $selection == *1* ]] && BUILD_KERNEL='on'
    [[ $selection == *2* ]] && CLEAN_KERNEL_SRC='on'
    [[ $selection == *3* ]] && ALLOW_KERNEL_CONFIG_CHANGES='on'
    [[ $selection == *4* ]] && BUILD_ROOTFS='on'
    [[ $selection == *5* ]] && ALLOW_ROOTFS_CHANGES='on'
    [[ $selection == *6* ]] && ALLOW_CMDLINE_CHANGES='on'
    [[ $selection == *7* ]] && ASK_EXTRA_PKGS='on'
    [[ $selection == *8* ]] && ZRAM_ENABLED='on'

else # at least kernel or rootfs has been selected via command line, check other options and set defaults
    [[ -z $CLEAN_KERNEL_SRC  ]] && CLEAN_KERNEL_SRC='off'
    [[ -z $ALLOW_KERNEL_CONFIG_CHANGES  ]] && ALLOW_KERNEL_CONFIG_CHANGES='off'

    [[ -z $ALLOW_ROOTFS_CHANGES  ]] && ALLOW_ROOTFS_CHANGES='off' 
    [[ -z $ASK_EXTRA_PKGS  ]] && ASK_EXTRA_PKGS='off'
    [[ -z $ZRAM_ENABLED  ]] && ZRAM_ENABLED='off'
fi


# inquire about further kernel configuration
if [[ $BUILD_KERNEL == "on" ]] && [ -z "$kernel_branch" ]; then
    display_select "Kernel Building" "Please select the Linux Kernel branch to build." \
        "4.18" "Linux kernel 4.18" \
        "5.6" "Linux kernel 5.6" \
        "5.8" "Linux kernel 5.8" \
        "5.10" "Linux kernel 5.10 LTS" \
        "5.11" "Linux kernel 5.11" \
        "5.12" "Linux kernel 5.12" \
        "5.13" "Linux kernel 5.13" \
        "5.14" "Linux kernel 5.14" \
        "5.15" "Linux kernel 5.15 LTS" \
        "5.16" "Linux kernel 5.16" \
        "5.17" "Linux kernel 5.17" \
        "5.18" "Linux kernel 5.18" \
        "6.0"  "Linux kernel 6.0" \
        "6.1"  "Linux kernel 6.1  LTS - Bookworm" \
        "6.3"  "Linux kernel 6.3" \
        "6.12" "Linux kernel 6.12 LTS - Trixie"

    ############################################################
    # Required gcc:
    #  armada370-gcc464_glibc215_hard_armada-GPL.txz (included in git)    FOR KERNEL VERSION <= 5.6
    #  gcc-arm-none-eabi (downloadable via apt)         FOR KERNEL VERSION >= 5.6
    # check toolchain subfolder for these or install via apt
    # Adjust makehelp to match path to your gcc:
    ############################################################
    if [[ $selection == "4.18" ]]; then
        makehelp='make CROSS_COMPILE=/opt/arm-marvell-linux-gnueabi/bin/arm-marvell-linux-gnueabi- ARCH=arm'   #FOR KERNEL VERSION <= 5.6 (via txz)
        display_result "Warning" "You have selected Linux Kernel 4.18, this will be build with older armada370 gcc464 toolchain, make sure you have extracted the txz file available in toolchain folder to /opt/"
    fi

    kernel_branch="linux-$selection.y"
fi
BACKTITLE+=" | "${kernel_branch}


# only allow building initramfs if rootfs build is enabled
if [[ $BUILD_ROOTFS == "on" ]] && [[ -z $BUILD_INITRAMFS ]]; then
    display_select "Build initramfs" "Do you want to build the initramfs?" \
    "y" "yes" \
    "n" "no"

    BUILD_INITRAMFS='off'

    [[ $selection == "y" ]] && BUILD_INITRAMFS='on'
fi

# get details for building the rootfs
if [[ $BUILD_ROOTFS == "on" ]]; then
    if [ -z "$release" ]; then
        display_select "Rootfs creation" "Please select the Debian release to build." \
            "trixie" "Debian Trixie" \
            "bookworm" "Debian Bookworm" \
            "bullseye" "Debian Bullseye" \
            "buster" "Debian Buster"

        release=$selection
    fi

    if [[ "$ASK_EXTRA_PKGS" == 'on' ]]; then
        display_input "Rootfs creation" "Type in any extra apt packages you want install. (Space separated)" "$EXTRA_PKGS"
        EXTRA_PKGS="$selection"
    fi

    if [[ -z "$BOOT_DEVICE" ]]; then
        display_select "Rootfs creation" "Please select which fstab to setup?" \
            "usb" "For usage with USB stick (boot on sdb1, root on sdb2)" \
            "hdd" "For usage with internal HDD (boot&root on sda3, data on sda2)"
        BOOT_DEVICE="$selection"
    fi

    if [[ "$BOOT_DEVICE" != "hdd" ]] && [[ "$BOOT_DEVICE" != "usb" ]]; then
        display_select "Rootfs creation" "Invalid boot device selected! Please choose:" \
            "usb" "For usage with USB stick (boot on sdb1, root on sdb2)" \
            "hdd" "For usage with internal HDD (boot&root on sda3, data on sda2)"
        BOOT_DEVICE="$selection"
    fi

    if [ -z "$root_pw" ]; then
        # Adjust default root pw
        display_input "Rootfs creation" "Type in the root password (Warning, root ssh will be enabled)" "1234"
        root_pw="$selection"
    fi

    if [ -z "$def_hostname" ]; then
        # Adjust hostname here
        display_input "Rootfs creation" "Type in the hostname for the WDMC" "wdmycloud"
        def_hostname="$selection"
    fi
fi
BACKTITLE+=" | "${release}

[[ $BUILD_KERNEL == "on" ]] && build_kernel
[[ $BUILD_ROOTFS == "on" ]] && build_root_fs
