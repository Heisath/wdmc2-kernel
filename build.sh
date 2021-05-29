#!/bin/bash

unalias -a

exit_with_error()
{
    echo $1
    exit 1
}
grab_version()
{
	local ver=()
	ver[0]=$(grep "^VERSION" "${1}"/Makefile | head -1 | awk '{print $(NF)}' | grep -oE '^[[:digit:]]+')
	ver[1]=$(grep "^PATCHLEVEL" "${1}"/Makefile | head -1 | awk '{print $(NF)}' | grep -oE '^[[:digit:]]+')
	ver[2]=$(grep "^SUBLEVEL" "${1}"/Makefile | head -1 | awk '{print $(NF)}' | grep -oE '^[[:digit:]]+')
	ver[3]=$(grep "^EXTRAVERSION" "${1}"/Makefile | head -1 | awk '{print $(NF)}' | grep -oE '^-rc[[:digit:]]+')
	echo "${ver[0]:-0}${ver[1]:+.${ver[1]}}${ver[2]:+.${ver[2]}}${ver[3]}"
}

display_yesno() {
  exec 3>&1
  dialog --title "$1" \
    --no-collapse \
    --yesno "$2" $DIALOG_HEIGHT $DIALOG_WIDTH
  exit_status=$?
  exec 3>&-
  case $exit_status in
    $DIALOG_CANCEL)
      selection='off'
      ;;
    $DIALOG_OK)
      selection='on'
      ;;
  esac
}

display_result() {
  dialog --title "$1" \
    --no-collapse \
    --msgbox "$2" $DIALOG_HEIGHT $DIALOG_WIDTH
}

display_select() {
  exec 3>&1
  selection=$(dialog \
    --backtitle "$BACKTITLE" \
    --title "$1" \
    --clear \
    --cancel-label "Exit" \
    --menu "$2" $DIALOG_HEIGHT $DIALOG_WIDTH 0 \
    "${@:3}" \
    2>&1 1>&3)
  exit_status=$?
  exec 3>&-
  case $exit_status in
    $DIALOG_CANCEL)
      echo "Program terminated."
      exit
      ;;
    $DIALOG_ESC)
      echo "Program aborted." >&2
      exit 1
      ;;
  esac
}

display_input() {
  exec 3>&1
  selection=$(dialog \
    --backtitle "$BACKTITLE" \
    --title "$1" \
    --clear \
    --cancel-label "Exit" \
    --inputbox "$2" $DIALOG_HEIGHT $DIALOG_WIDTH "$3" \
    2>&1 1>&3)
  exit_status=$?
  exec 3>&-
  case $exit_status in
    $DIALOG_CANCEL)
      echo "Program terminated."
      exit
      ;;
    $DIALOG_ESC)
      echo "Program aborted." >&2
      exit 1
      ;;
  esac
}

display_checklist() {
  exec 3>&1
  selection=$(dialog \
    --backtitle "$BACKTITLE" \
    --title "$1" \
    --clear \
    --cancel-label "Exit" \
    --checklist "$2" $DIALOG_HEIGHT $DIALOG_WIDTH 0 \
    "${@:3}" \
    2>&1 1>&3)
  exit_status=$?
  exec 3>&-

  case $exit_status in
    $DIALOG_CANCEL)
      echo "Program terminated."
      exit
      ;;
    $DIALOG_ESC)
      echo "Program aborted." >&2
      exit 1
      ;;
  esac
}

read_arguments() {
    # read command line to replace defaults
    POSITIONAL=()
    while [[ $# -gt 0 ]]
    do
        key="$1"
        value="$2"

        case $key in
            # feature selection
            --kernel)
                BUILD_KERNEL='on'
                shift;
            ;;
            --clean)
                CLEAN_KERNEL_SRC='on'
                shift;
            ;;
            --config)
                ALLOW_KERNEL_CONFIG_CHANGES='on'
                shift;
            ;;


            --rootfs)
                BUILD_ROOTFS='on'
                shift;
            ;;
            --changes)
                ALLOW_ROOTFS_CHANGES='on'
                shift;
            ;;
	        --initramfs)
	            BUILD_INITRAMFS='on'
	            shift;
            ;;
	        
	    
            --ghrunner)
                BUILD_KERNEL='on'
                CLEAN_KERNEL_SRC='on'
                ALLOW_KERNEL_CONFIG_CHANGES='off'

                BUILD_INITRAMFS='off'
                BUILD_ROOT='off'
                
                kernel_branch='linux-5.10.y'
                
                GHRUNNER='on'
                THREADS=2


                shift;
            ;;
            
            
            #  config selection
        
            --release)
                release=${value}
                shift; shift
            ;;
            --root-pw)
                root_pw=${value}
                shift; shift
            ;;
            --hostname)
                def_hostname=${value}
                shift; shift;
            ;;
            --kernelbranch)
                kernel_branch=${value}
                shift; shift;
            ;;
            --zram) 
                ZRAM_ENABLED='on'
                shift;
            ;;

            --boot)
                BOOT_DEVICE=${value}
                shift; shift;
            ;;
            
            *)    # unknown option
                POSITIONAL+=("$1") # save it in an array for later
                shift # past argument
            ;;
        esac
    done
}

build_kernel()
{
    # do preparation steps
    echo "### Cloning linux kernel $kernel_branch"

    if [[ $kernel_branch == *linux* ]]; then
        kernel_dir="${cache_dir}/$kernel_branch";
        kernel_config="config/$kernel_branch.config";
    else
        kernel_dir="${cache_dir}/linux-$kernel_branch";
        kernel_config="config/linux-$kernel_branch.config";
    fi

    # generate output directory
    mkdir -p "${output_dir}"
    mkdir -p "${boot_dir}"

    if [ ! -d ${kernel_dir} ]; then
        echo "### Kernel dir does not exist, cloning kernel"

        mkdir -p "${kernel_dir}"

        # git clone linux tree
        git clone --branch "$kernel_branch" --depth 1 https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git "${kernel_dir}"
    else
        if [ ${CLEAN_KERNEL_SRC} = 'on' ]; then
            echo "### Kernel dir does exist. Fetching and cleaning"
            echo "### If you want to skip this step provide --noclean"

            cd ${kernel_dir}

            git fetch --depth 1 origin "$kernel_branch"

            git checkout -f -q FETCH_HEAD
            git clean -qdf

            cd ${current_dir}
        else
            echo "### Kernel dir does exist. --noclean provided"
            echo "### Continuing with dirty kernel src"

        fi

    fi


    # copy config and dts
    echo "### Moving kernel config in place"

    if [ ! -f ${kernel_config} ]; then
        cp config/linux-default.config ${kernel_config}
    fi

    cp "${kernel_config}" "${kernel_dir}"/.config
    cp dts/*.dts "${kernel_dir}"/arch/arm/boot/dts/

    kernel_version=$(grab_version "${kernel_dir}");
    
    # cleanup old modules for this kernel
    rm -r "${output_dir}"/lib/modules/"$kernel_version"
    
    # cd into linux source
    cd "${kernel_dir}"

    echo "### Starting make"

    if [ ${ALLOW_KERNEL_CONFIG_CHANGES} = 'on' ]; then
        $makehelp menuconfig
    fi
    $makehelp -j${THREADS} zImage
    $makehelp -j${THREADS} armada-375-wdmc-gen2.dtb
    cat arch/arm/boot/zImage arch/arm/boot/dts/armada-375-wdmc-gen2.dtb > zImage_and_dtb
    mkimage -A arm -O linux -T kernel -C none -a 0x00008000 -e 0x00008000 -n 'WDMC-Gen2' -d zImage_and_dtb "${boot_dir}"/uImage-${kernel_version}
    rm zImage_and_dtb

    $makehelp -j${THREADS} modules
    $makehelp -j${THREADS} INSTALL_MOD_PATH="${output_dir}" modules_install

    cd "${current_dir}"

    echo "### Copying new kernel config to output"
    cp "${kernel_dir}"/.config "${boot_dir}"/linux-${kernel_version}.config

    echo "### Adding default ramdisk to output"
    cp prebuilt/uRamdisk "${boot_dir}"

    # set permissions for later runnable files
    chmod =rwxrxrx "${boot_dir}"/uRamdisk
    chmod =rwxrxrx "${boot_dir}"/uImage-${kernel_version}

    cp "${boot_dir}"/uImage-${kernel_version} "${boot_dir}"/uImage

    echo "### Cleanup and tar results"
    rm "${output_dir}"/lib/modules/*/source
    rm "${output_dir}"/lib/modules/*/build

    # tar and compress modules for easier transport
    cd "${output_dir}"/lib/modules/
    tar -czf "${output_dir}"/modules-${kernel_version}.tar.gz "${kernel_version}"

    cd "${output_dir}"
    tar -czf "${output_dir}"/boot-${kernel_version}.tar.gz boot/uRamdisk boot/uImage-${kernel_version} boot/uImage boot/linux-${kernel_version}.config

    rm "${boot_dir}"/uImage

    cd "${current_dir}"
    
    # abort point for github runner to keep it from messing with permissions
    if [[ $GHRUNNER == 'on' ]]; then
        return
    fi

    # fix permissions on folders for usability
    chown "root:sudo" "${cache_dir}"
    chown "root:sudo" "${cache_dir}"/*
  	
    chown "root:sudo" "${output_dir}"
    chown -R "root:sudo" "${boot_dir}"
    chown "root:sudo" "${output_dir}"/lib

    chown "${current_user}:sudo" "${output_dir}"/linux-${kernel_version}.config
    chown "${current_user}:sudo" "${output_dir}"/modules-${kernel_version}.tar.gz
    chown "${current_user}:sudo" "${output_dir}"/boot-${kernel_version}.tar.gz

    chmod "g+rw" "${cache_dir}"
    chmod "g+rw" "${cache_dir}"/*
    chmod "g+rw" "${output_dir}"
    chmod -R "g+rw" "${boot_dir}"
    chmod "g+rw" "${output_dir}"/lib
    
}

build_root_fs()
{
    # setup some more or less static config variables
    arch='armhf'
    qemu_binary='qemu-arm-static'
    components='main,contrib'
    # Adjust package list here
    includes="ccache,locales,git,ca-certificates,debhelper,rsync,python3,distcc,systemd,init,udev,kmod,busybox,ethtool,dirmngr,hdparm,ifupdown,iproute2,iputils-ping,logrotate,net-tools,nftables,powermgmt-base,procps,rename,resolvconf,rsyslog,ssh,sysstat,update-inetd,isc-dhcp-client,isc-dhcp-common,vim,dialog,apt-utils,nano,keyboard-configuration,console-setup,linux-base,cpio,u-boot-tools,bc" 
    mirror_addr="http://httpredir.debian.org/debian/"

    # cleanup old
    rm -rf "${rootfs_dir}"
    rm -rf "${output_dir}"/"${release}"-rootfs.tar.gz

    # generate output directory
    mkdir -p "${rootfs_dir}"

    echo "### Creating build chroot: $release/$arch"

    rootfs_cache_valid='no';
    if [ -f "${cache_dir}"/"${release}"-rootfs-cache.tar.gz ]; then
        cd "${rootfs_dir}"
        tar -xzf "${cache_dir}"/"${release}"-rootfs-cache.tar.gz
        cd "${current_dir}"

        . "${rootfs_dir}"/root/.debootstrap-info
        if  [ "${dbs_arch}" = "${arch}" ] &&
            [ "${dbs_release}" = "${release}" ] &&
            [ "${dbs_components}" = "${components}" ] &&
            [ "${dbs_includes}" = "${includes}" ]; then
            echo "### Found valid rootfs cache"
            rootfs_cache_valid='yes';
        else
            rm -rf "${rootfs_dir}"
            mkdir -p "${rootfs_dir}"
        fi
    fi

    if [[ ${rootfs_cache_valid} == 'no' ]]; then
        echo "### Creating new rootfs"

        debootstrap --variant=minbase --arch="${arch}" --foreign --components="${components}" --include="${includes}" "${release}" "${rootfs_dir}" "${mirror_addr}"
        [[ $? -ne 0 || ! -f "${rootfs_dir}"/debootstrap/debootstrap ]] && exit_with_error "### Create chroot first stage failed"

        echo "### First stage completed"

        cp /usr/bin/"${qemu_binary}" "${rootfs_dir}"/usr/

        mkdir -p  "${rootfs_dir}"/usr/share/keyrings/
        cp /usr/share/keyrings/*-archive-keyring.gpg "${rootfs_dir}"/usr/share/keyrings/

        echo "### Copied qemu and keyring"

        chroot "${rootfs_dir}" /bin/bash -c "/debootstrap/debootstrap --second-stage"
        [[ $? -ne 0 || ! -f "${rootfs_dir}"/bin/bash ]] && exit_with_error "### Create chroot second stage failed"
        echo "### Second stage completed"
        touch "${rootfs_dir}"/root/.debootstrap-complete

        echo "### Creating rootfs cache for future builds"
        cat << EOF > "${rootfs_dir}"/root/.debootstrap-info
dbs_arch=${arch}
dbs_release=${release}
dbs_components=${components}
dbs_includes=${includes}
EOF
        cd "${rootfs_dir}"
        tar -czf "${cache_dir}"/"${release}"-rootfs-cache.tar.gz .
        cd "${current_dir}"
    fi

    echo "### Mounting / preparing chroot"
    mount -t proc chproc "${rootfs_dir}"/proc
    mount -t sysfs chsys "${rootfs_dir}"/sys
    mount -t devtmpfs chdev "${rootfs_dir}"/dev || mount --bind /dev "${rootfs_dir}"/dev
    mount -t devpts chpts "${rootfs_dir}"/dev/pts

    echo "### Copying files from tweaks folder"
    cp -a tweaks/* "${rootfs_dir}"
    
    echo "### Adjusting fstab"
    [[ "$BOOT_DEVICE" == 'usb' ]] && cp "${rootfs_dir}"/etc/fstab.usb "${rootfs_dir}"/etc/fstab
    [[ "$BOOT_DEVICE" == 'hdd' ]] && cp "${rootfs_dir}"/etc/fstab.hdd "${rootfs_dir}"/etc/fstab    
    
    echo "### Running apt in chroot"
    sed -i -e "s/_release_/$release/g" "${rootfs_dir}/etc/apt/sources.list"

    chroot "${rootfs_dir}" /bin/bash -c "apt-get -y update"
    chroot "${rootfs_dir}" /bin/bash -c "apt-get -y full-upgrade"
    chroot "${rootfs_dir}" /bin/bash -c "apt-get -y install ${EXTRA_PKGS}"
    chroot "${rootfs_dir}" /bin/bash -c "apt-get -y autoremove"
    chroot "${rootfs_dir}" /bin/bash -c "apt-get -y clean"

    echo "### Applying tweaks"
    [[ -f "${rootfs_dir}"/etc/locale.gen ]] && sed -i "s/^# en_US.UTF-8/en_US.UTF-8/" "${rootfs_dir}"/etc/locale.gen
    #chroot "${rootfs_dir}" /bin/bash -c "locale-gen; update-locale LANG=en_US:en LC_ALL=en_US.UTF-8"
    chroot "${rootfs_dir}" /bin/bash -c "dpkg-reconfigure locales"
    chroot "${rootfs_dir}" /bin/bash -c "dpkg-reconfigure tzdata"
    chroot "${rootfs_dir}" /bin/bash -c "dpkg-reconfigure keyboard-configuration"
    chroot "${rootfs_dir}" /bin/bash -c "/usr/sbin/update-ccache-symlinks"

    # set root password
    echo "### Root password set to ${root_pw}"
    chroot "${rootfs_dir}" /bin/bash -c "(echo ${root_pw};echo ${root_pw};) | passwd root >/dev/null 2>&1"

    # permit root login via SSH for the first boot
    sed -i 's/#\?PermitRootLogin .*/PermitRootLogin yes/' "${rootfs_dir}"/etc/ssh/sshd_config

    # Setup hostname
    echo ${def_hostname} > ${rootfs_dir}/etc/hostname

    # Enable zram (swap and logging)
    if [[ ${ZRAM_ENABLED} == 'on' ]]; then
        chroot ${rootfs_dir} systemctl enable armbian-zram-config.service
        chroot ${rootfs_dir} systemctl enable armbian-ramlog.service
    fi

    if [[ ${BUILD_KERNEL} == 'on' ]]; then
        cp "${boot_dir}"/uRamdisk "${rootfs_dir}"/boot/
        cp "${boot_dir}"/uImage-$kernel_version "${rootfs_dir}"/boot/
        cp "${boot_dir}"/uImage-$kernel_version "${rootfs_dir}"/boot/uImage
        cp -R "${output_dir}"/lib/* "${rootfs_dir}"/lib/
    fi

    cp build_initramfs.sh "${rootfs_dir}"/root/
    if [[ ${BUILD_INITRAMFS} == 'on' ]]; then
        chroot "${rootfs_dir}" /bin/bash -c "/root/build_initramfs.sh --update"
    fi

    if [[ ${ALLOW_ROOTFS_CHANGES} == 'on' ]]; then
        echo "### You can now adjust the rootfs in output/rootfs/"
        read -r -p "### Press any key to continue and pack it up..." -n1
    fi

    echo "### Unmounting"
    while grep -Eq "${rootfs_dir}.*(dev|proc|sys)" /proc/mounts
    do
        umount -l --recursive "${rootfs_dir}"/dev >/dev/null 2>&1
        umount -l "${rootfs_dir}"/proc >/dev/null 2>&1
        umount -l "${rootfs_dir}"/sys >/dev/null 2>&1
        sleep 5
    done

    echo "### Rootfs complete: ${release}/${arch}"
    echo "### Packing and cleanup"

    cd "${rootfs_dir}"

    tar -czf "${output_dir}"/"${release}"-rootfs.tar.gz .

    chown "root:sudo" "${rootfs_dir}"
    chown "root:sudo" "${output_dir}"/"${release}"-rootfs.tar.gz
    chmod "g+rw" "${rootfs_dir}"
    chmod "g+rw" "${output_dir}"/"${release}"-rootfs.tar.gz

}

############################################################
### Script starts here
############################################################


# Find dir of build.sh and go there
current_dir="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
# check for whitespace in ${current_dir} and exit for safety reasons
grep -q "[[:space:]]" <<<"${current_dir}" && { echo "\"${current_dir}\" contains whitespace. Aborting." >&2 ; exit 1 ; }
cd "${current_dir}" || exit

DIALOG_CANCEL=1
DIALOG_ESC=255
BACKTITLE="WDMC kernel & rootfs build script"

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
    echo "This script requires root privileges, please rerun using sudo"
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
    ASK_EXTRA_PKGS='off'
    ZRAM_ENABLED='on'

    # Show user checklist to select
    display_checklist "Build setup" "Select components and options for build:" \
        "1" "Linux Kernel" "$BUILD_KERNEL" \
        "2" "Clean Kernel sources" "$CLEAN_KERNEL_SRC" \
        "3" "Allow Kernel config changes" "$ALLOW_KERNEL_CONFIG_CHANGES" \
        "4" "Debian Rootfs" "$BUILD_ROOTFS" \
        "5" "Allow Rootfs changes" "$ALLOW_ROOTFS_CHANGES" \
        "6" "Ask for extra apt pkgs" "$ASK_EXTRA_PKGS" \
        "7" "Enable ZRAM on rootfs" "$ZRAM_ENABLED" 
        
    # Accept user choices
    BUILD_KERNEL='off'
    CLEAN_KERNEL_SRC='off'
    ALLOW_KERNEL_CONFIG_CHANGES='off'
    BUILD_ROOTFS='off'
    ALLOW_ROOTFS_CHANGES='off'
    ASK_EXTRA_PKGS='off'
    ZRAM_ENABLED='off'

    [[ $selection == *1* ]] && BUILD_KERNEL='on'
    [[ $selection == *2* ]] && CLEAN_KERNEL_SRC='on'
    [[ $selection == *3* ]] && ALLOW_KERNEL_CONFIG_CHANGES='on'
    [[ $selection == *4* ]] && BUILD_ROOTFS='on'
    [[ $selection == *5* ]] && ALLOW_ROOTFS_CHANGES='on'
    [[ $selection == *6* ]] && ASK_EXTRA_PKGS='on'
    [[ $selection == *7* ]] && ZRAM_ENABLED='on'
else # at least kernel or rootfs has been selected via command line, check other options and set defaults
    [[ -z $CLEAN_KERNEL_SRC  ]] && CLEAN_KERNEL_SRC='on'
    [[ -z $ALLOW_KERNEL_CONFIG_CHANGES  ]] && ALLOW_KERNEL_CONFIG_CHANGES='off'
        
    [[ -z $ALLOW_ROOTFS_CHANGES  ]] && ALLOW_ROOTFS_CHANGES='off'    
    [[ -z $ASK_EXTRA_PKGS  ]] && ASK_EXTRA_PKGS='off'
    [[ -z $ZRAM_ENABLED  ]] && ZRAM_ENABLED='on' 
fi

if [[ $BUILD_KERNEL == "on" ]] && [ -z "$kernel_branch" ]; then
    display_select "Kernel Building" "Please select the Linux Kernel branch to build." \
        "4.18" "Linux kernel 4.18" \
        "5.6" "Linux kernel 5.6" \
        "5.8" "Linux kernel 5.8" \
        "5.10" "Linux kernel 5.10" \
        "5.11" "Linux kernel 5.11" \
        "5.12" "Linux kernel 5.12"
        
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

if [[ $BUILD_ROOTFS == "on" ]]; then
    if [ -z "$release" ]; then
        display_select "Rootfs creation" "Please select the Debian release to build." \
            "buster" "Debian Buster" \
            "bullseye" "Debian Bullseye" 

        release=$selection
    fi

    if [[ "$ASK_EXTRA_PKGS" == 'on' ]]; then
        display_input "Rootfs creation" "Type in any extra apt packages you want install. (Space seperated)" "$EXTRA_PKGS"
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
