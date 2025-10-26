#!/bin/bash

build_root_fs()
{
    # setup some more or less static config variables
    arch='armhf'
    qemu_binary='qemu-arm-static'
    components='main,contrib'
    # Adjust package list here
    includes="bash,ccache,locales,git,ca-certificates,debhelper,rsync,python3,systemd,systemd-timesyncd,init,udev,kmod,busybox-static,ethtool,dirmngr,hdparm,ifupdown,iproute2,iputils-ping,logrotate,net-tools,nftables,powermgmt-base,procps,rename,resolvconf,rsyslog,ssh,sysstat,update-inetd,isc-dhcp-client,isc-dhcp-common,vim,dialog,apt-utils,nano,keyboard-configuration,console-setup,linux-base,cpio,u-boot-tools,bc,dbus"
    mirror_addr="https://deb.debian.org/debian/"

    if [ "${release}" == "trixie" ]; then
        kludge="--no-check-gpg"
        includes="$includes,e2fsck-static"
        # wget https://deb.debian.org/debian/dists/trixie/Release.gpg -qO /tmp/debian-release.gpg \
        # kludge="--keyring=/tmp/debian-release.gpg"
    fi

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

        debootstrap ${kludge} --variant=minbase --arch="${arch}" --foreign --components="${components}" --include="${includes}" "${release}" "${rootfs_dir}" "${mirror_addr}"
        [[ $? -ne 0 || ! -f "${rootfs_dir}"/debootstrap/debootstrap ]] && exit_with_error "### Create chroot first stage failed"

        echo "### First stage completed"

        cp /usr/bin/"${qemu_binary}" "${rootfs_dir}"/usr/bin/

        mkdir -p  "${rootfs_dir}"/usr/share/keyrings/
        cp /usr/share/keyrings/*-archive-keyring.gpg "${rootfs_dir}"/usr/share/keyrings/

        echo "### Copied qemu and keyring"
        echo "${rootfs_dir}"

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
    [[ "$BOOT_DEVICE" == 'usb' ]] && chroot "${rootfs_dir}" /bin/bash -c "ln -rsf /etc/fstab.usb /etc/fstab"
    [[ "$BOOT_DEVICE" == 'hdd' ]] && chroot "${rootfs_dir}" /bin/bash -c "ln -rsf /etc/fstab.hdd /etc/fstab"

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
        echo "### Enable ZRAM"
        chroot ${rootfs_dir} systemctl enable armbian-zram-config.service
        chroot ${rootfs_dir} systemctl enable armbian-ramlog.service
    else
        echo "### Enable SWAP"
        chroot ${rootfs_dir} systemctl disable armbian-zram-config.service
        chroot ${rootfs_dir} systemctl disable armbian-ramlog.service
        sed -i 's|#/dev/sda1|/dev/sda1 |' "${rootfs_dir}"/etc/fstab.hdd
        sed -i 's|#/dev/sdb3|/dev/sdb3 |' "${rootfs_dir}"/etc/fstab.usb
        sed -i 's|#tmpfs|tmpfs |' "${rootfs_dir}"/etc/fstab.hdd
        sed -i 's|#tmpfs|tmpfs |' "${rootfs_dir}"/etc/fstab.usb
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
        read -r -p "### Press any key to continue..." -n1
    fi

    if [[ ${ALLOW_CMDLINE_CHANGES} == 'on' ]]; then
        echo "### Will now enter a root bash in the new rootfs"
        echo "### Once you are done making changes, 'exit' to continue..."
        chroot "${rootfs_dir}" /bin/bash
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
