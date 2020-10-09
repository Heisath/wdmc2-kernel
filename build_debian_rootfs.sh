#!/bin/bash

exit_with_error() 
{
    echo $1
    exit 1
}


# we can never know what aliases may be set, so remove them all
unalias -a

# do preparation steps
target_dir="output/rootfs"

# cleanup old
rm -rf "${target_dir}"

# set options
release='buster'
arch='armhf'
qemu_binary='qemu-arm-static'
components='main,contrib'
includes="ccache,locales,git,ca-certificates,debhelper,rsync,python3,distcc,systemd,init,udev,kmod,bash-completion,busybox,ethtool,dirmngr,hdparm,ifupdown,iproute2,iputils-ping,logrotate,net-tools,nftables,powermgmt-base,procps,rename,resolvconf,rsyslog,ssh,sysstat,update-inetd" #libfile-fcntllock-perl,devscripts,
mirror_addr="http://httpredir.debian.org/debian/"

# generate output directory
mkdir -p $target_dir

echo "### Creating build chroot: $release/$arch"

# 

debootstrap --variant=minbase --arch="${arch}" --foreign --components="${components}" --include="${includes}" "${release}" "${target_dir}" "${mirror_addr}"
[[ $? -ne 0 || ! -f $target_dir/debootstrap/debootstrap ]] && exit_with_error "### Create chroot first stage failed"

echo "### First stage completed"

cp /usr/bin/$qemu_binary $target_dir/usr/bin/

mkdir -p  $target_dir/usr/share/keyrings/
cp /usr/share/keyrings/*-archive-keyring.gpg $target_dir/usr/share/keyrings/


chroot "${target_dir}" /bin/bash -c "/debootstrap/debootstrap --second-stage"
[[ $? -ne 0 || ! -f "${target_dir}"/bin/bash ]] && exit_with_error "### Create chroot second stage failed"
echo "### Second stage completed"

mount -t proc chproc "${target_dir}"/proc
mount -t sysfs chsys "${target_dir}"/sys
mount -t devtmpfs chdev "${target_dir}"/dev || mount --bind /dev "${target_dir}"/dev
mount -t devpts chpts "${target_dir}"/dev/pts


[[ -f $target_dir/etc/locale.gen ]] && sed -i "s/^# en_US.UTF-8/en_US.UTF-8/" $target_dir/etc/locale.gen
chroot $target_dir /bin/bash -c "locale-gen; update-locale LANG=en_US:en LC_ALL=en_US.UTF-8"
chroot $target_dir /bin/bash -c "/usr/sbin/update-ccache-symlinks"

if [[ -f $target_dir/etc/default/console-setup ]]; then
	sed -e 's/CHARMAP=.*/CHARMAP="UTF-8"/' -e 's/FONTSIZE=.*/FONTSIZE="8x16"/' \
		-e 's/CODESET=.*/CODESET="guess"/' -i $target_dir/etc/default/console-setup
	eval 'LC_ALL=C LANG=C chroot $target_dir /bin/bash -c "setupcon --save"'
fi

chroot "${target_dir}" /bin/bash -c "apt-get -y update"
chroot "${target_dir}" /bin/bash -c "apt-get -y install systemd init udev kmod bash-completion busybox ethtool dirmngr hdparm ifupdown iproute2 iproute iftables iputils-ping logrotate net-tools nftables powermgmt-base procps rename resolvconf rsyslog ssh sysstat update-inetd"

chroot "${target_dir}" /bin/bash -c "apt-get -y full-upgrade"
chroot "${target_dir}" /bin/bash -c "apt-get -y autoremove"
chroot "${target_dir}" /bin/bash -c "apt-get -y clean"

# set root password
chroot "${target_dir}" /bin/bash -c "(echo 1234;echo 1234;) | passwd root >/dev/null 2>&1"



while grep -Eq "${target_dir}.*(dev|proc|sys)" /proc/mounts
do
	umount -l --recursive "${target_dir}"/dev >/dev/null 2>&1
	umount -l "${target_dir}"/proc >/dev/null 2>&1
	umount -l "${target_dir}"/sys >/dev/null 2>&1
	sleep 5
done

touch "${target_dir}"/root/.debootstrap-complete
echo "### Debootstrap complete: ${release}/${arch}"

cat << EOF > ${target_dir}/etc/fstab
# Default mounts
/dev/sdb2       /               ext4    defaults,noatime,nodiratime,commit=600,errors=remount-ro 0 1
#/dev/sdb1       /boot           auto    defaults                0       0

proc            /proc           proc    defaults                0       0
#devpts         /dev/pts        devpts  defaults,gid5,mode=620  0       0
tmpfs           /dev/shm        tmpfs   mode=0777               0       0
tmpfs           /tmp            tmpfs   mode=1777               0       0
tmpfs           /run            tmpfs   mode=0755,nosuid,nodev  0       0
sysfs           /sys            sysfs   defaults                0       0

# Add swap
#/dev/sdb3      swap            swap    defaults                0       0

# Add internal harddisk
#/dev/sda1       /mnt/hd-intern  ext4    defaults,noatime        0       1
EOF

cat << EOF > ${target_dir}/etc/hostname
wdmycloudusb
EOF

cd "${target_dir}"

tar -czf ../"${release}"-rootfs.tar.gz .
