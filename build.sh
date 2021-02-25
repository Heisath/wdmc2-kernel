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

current_dir="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"

# check for whitespace in ${current_dir} and exit for safety reasons
grep -q "[[:space:]]" <<<"${current_dir}" && { echo "\"${current_dir}\" contains whitespace. Aborting." >&2 ; exit 1 ; }

cd "${current_dir}" || exit

output_dir="${current_dir}/output"
rootfs_dir="${output_dir}/rootfs"
boot_dir="${output_dir}/boot"
cache_dir="${current_dir}/cache"

current_user="$(stat --format %U "${current_dir}"/.git)"

#Required gcc:
#  armada370-gcc464_glibc215_hard_armada-GPL.txz (included in git)    FOR KERNEL VERSION <= 5.6
#  gcc-arm-none-eabi (downloadable via apt / included in git)         FOR KERNEL VERSION >= 5.6
# check toolchain subfolder for these or install via apt
#Adjust makehelp to match path to your gcc:
#makehelp='make CROSS_COMPILE=/opt/arm-marvell-linux-gnueabi/bin/arm-marvell-linux-gnueabi- ARCH=arm'   #FOR KERNEL VERSION <= 5.6 (via txz)
makehelp='make CROSS_COMPILE=/opt/gcc-arm-none-eabi/bin/arm-none-eabi- ARCH=arm'                        #FOR KERNEL VERSION >= 5.6 (via txz)
#makehelp='make CROSS_COMPILE=/usr/bin/arm-none-eabi- ARCH=arm'                                         #FOR KERNEL VERSION >= 5.6 (via apt)

# default config values
release='buster'
arch='armhf'
qemu_binary='qemu-arm-static'
components='main,contrib'
# Adjust package list here
includes="ccache,locales,git,ca-certificates,debhelper,rsync,python3,distcc,systemd,init,udev,kmod,busybox,ethtool,dirmngr,hdparm,ifupdown,iproute2,iputils-ping,logrotate,net-tools,nftables,powermgmt-base,procps,rename,resolvconf,rsyslog,ssh,sysstat,update-inetd,isc-dhcp-client,isc-dhcp-common,vim,dialog,apt-utils,nano,keyboard-configuration,console-setup,linux-base,cpio,u-boot-tools" 
mirror_addr="http://httpredir.debian.org/debian/"

# Adjust default root pw
root_pw='1234'

# Adjust hostname here
def_hostname='wdmycloud'

kernel_branch='linux-5.10.y'

BUILD_KERNEL='yes'
BUILD_ROOT='yes'
BUILD_INITRAMFS='yes'
ALLOW_ROOTFS_CHANGES='no'
CLEAN_KERNEL_SRC='yes'
ALLOW_KERNEL_CONFIG_CHANGES='yes'

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
        if [ ${CLEAN_KERNEL_SRC} = 'yes' ]; then
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

    # cd into linux source
    cd "${kernel_dir}"

    echo "### Starting make"

    if [ ${ALLOW_KERNEL_CONFIG_CHANGES} = 'yes' ]; then
        $makehelp menuconfig
    fi
    $makehelp -j8 zImage
    $makehelp -j8 armada-375-wdmc-gen2.dtb
    cat arch/arm/boot/zImage arch/arm/boot/dts/armada-375-wdmc-gen2.dtb > zImage_and_dtb
    mkimage -A arm -O linux -T kernel -C none -a 0x00008000 -e 0x00008000 -n 'WDMC-Gen2' -d zImage_and_dtb "${boot_dir}"/uImage-${kernel_version}
    rm zImage_and_dtb

    $makehelp -j8 modules
    $makehelp -j8 INSTALL_MOD_PATH="${output_dir}" modules_install

    cd "${current_dir}"

    echo "### Copying new kernel config to output"
    cp "${kernel_dir}"/.config "${output_dir}"/linux-${kernel_version}.config

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
    tar -czf "${output_dir}"/boot-${kernel_version}.tar.gz boot/uRamdisk boot/uImage-${kernel_version} boot/uImage
    
    rm "${boot_dir}"/uImage
    
    cd "${current_dir}"
   
    echo "### Finishing"
    # fix permissions on folders for usability
    chown "root:sudo" "${cache_dir}"
    chown "root:sudo" "${output_dir}"
    chown -R "root:sudo" "${boot_dir}"
    chown "root:sudo" "${output_dir}"/lib
    
    chown "${current_user}:sudo" "${output_dir}"/linux-${kernel_version}.config
    chown "${current_user}:sudo" "${output_dir}"/modules-${kernel_version}.tar.gz
    chown "${current_user}:sudo" "${output_dir}"/boot-${kernel_version}.tar.gz

    chmod "g+rw" "${cache_dir}"    
    chmod "g+rw" "${output_dir}"
    chmod -R "g+rw" "${boot_dir}"
    chmod "g+rw" "${output_dir}"/lib
}

build_root_fs() 
{
    # cleanup old
    rm -rf "${rootfs_dir}"
    rm -rf "${output_dir}"/"${release}"-rootfs.tar.gz

    # generate output directory
    mkdir -p ${rootfs_dir}

    echo "### Creating build chroot: $release/$arch"

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

    echo "### Mounting / preparing chroot"
    mount -t proc chproc "${rootfs_dir}"/proc
    mount -t sysfs chsys "${rootfs_dir}"/sys
    mount -t devtmpfs chdev "${rootfs_dir}"/dev || mount --bind /dev "${rootfs_dir}"/dev
    mount -t devpts chpts "${rootfs_dir}"/dev/pts

    echo "### Addings sources list and updating"
    . tweaks/aptsources.sh
    . tweaks/extrapkgs.sh

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

    # create fstab, adjust for your layout here
    . tweaks/fstab.sh

    # Apply tweaks in sysctl
    . tweaks/sysctl.sh

    # Setup hostname
    echo ${def_hostname} > ${rootfs_dir}/etc/hostname

    # Setup interfaces (eth0)
    . tweaks/interfaces.sh

    if [ ${BUILD_KERNEL} = 'yes' ] 
    then
        cp "${boot_dir}"/uRamdisk "${rootfs_dir}"/boot/
        cp "${boot_dir}"/uImage-$kernel_version "${rootfs_dir}"/boot/
        cp "${boot_dir}"/uImage-$kernel_version "${rootfs_dir}"/boot/uImage
        cp -R "${output_dir}"/lib/* "${rootfs_dir}"/lib/
    fi

    cp build_initramfs.sh "${rootfs_dir}"/root/
    if [ ${BUILD_INITRAMFS} = 'yes' ]
    then
        chroot "${rootfs_dir}" /bin/bash -c "/root/build_initramfs.sh --update"
    fi

    if [ ${ALLOW_ROOTFS_CHANGES} = 'yes' ]
    then 
        echo "### You can now adjust the rootfs"
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

    touch "${rootfs_dir}"/root/.debootstrap-complete
    echo "### Debootstrap complete: ${release}/${arch}"
   

    cd "${rootfs_dir}"
    
    tar -czf "${output_dir}"/"${release}"-rootfs.tar.gz .
    
    chown "root:sudo" "${rootfs_dir}"
    chown "root:sudo" "${output_dir}"/"${release}"-rootfs.tar.gz
    chmod "g+rw" "${rootfs_dir}"
    chmod "g+rw" "${output_dir}"/"${release}"-rootfs.tar.gz
}

if [[ "${EUID}" != "0" ]]; then
	echo "This script requires root privileges, please rerun using sudo"
	exit 1
fi

# read command line to replace defaults 
POSITIONAL=()
while [[ $# -gt 0 ]]
do
    key="$1"
    value="$2"

    DEBUG=0
    case $key in
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
        --kernel)
            kernel_branch=${value}
            shift; shift;
        ;;
        
        --noclean) 
            CLEAN_KERNEL_SRC='no'
            shift;
        ;;
        --noconfig)
            ALLOW_KERNEL_CONFIG_CHANGES='no'
            shift;
        ;;
        
        --kernelonly)
            BUILD_ROOT='no'
            BUILD_INITRAMFS='no'
            shift;
        ;;
        --rootonly)
            BUILD_KERNEL='no'
            BUILD_INITRAMFS='no'
            shift;
        ;;
        --nokernel)
            BUILD_KERNEL='no'
            shift;
        ;;
        --noinitramfs)
            BUILD_INITRAMFS='no'
            shift;
        ;;

        --changes) 
            ALLOW_ROOTFS_CHANGES='yes'
            shift;
        ;;
        *)    # unknown option
            POSITIONAL+=("$1") # save it in an array for later
            shift # past argument
        ;;
    esac
done

echo '### Build options'

echo "Build dir: ${current_dir}"

if [ ${BUILD_KERNEL} = 'yes' ] 
then
    echo "Kernel ${kernel_branch}"
fi

if [ ${BUILD_ROOT} = 'yes' ]
then
    echo "Rootfs ${release} , Hostname ${def_hostname}"
    echo "Build initramfs: $BUILD_INITRAMFS"
    echo "Allow rootfs changes: $ALLOW_ROOTFS_CHANGES"
fi


sleep 5
echo '### Starting build'

if [ ${BUILD_KERNEL} = 'yes' ] 
then
    build_kernel
fi
if [ ${BUILD_ROOT} = 'yes' ]
then
   build_root_fs
fi


