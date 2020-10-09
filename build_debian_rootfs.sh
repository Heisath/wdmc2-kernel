#!/bin/bash

exit_with_error() 
{
    echo $1
    exit 1
}


# we can never know what aliases may be set, so remove them all
unalias -a

# set options
target_dir="output"
rootfs="${target_dir}"/rootfs
release='buster'
arch='armhf'
qemu_binary='qemu-arm-static'
components='main,contrib'
includes="ccache,locales,git,ca-certificates,debhelper,rsync,python3,distcc,systemd,init,udev,kmod,bash-completion,busybox,ethtool,dirmngr,hdparm,ifupdown,iproute2,iputils-ping,logrotate,net-tools,nftables,powermgmt-base,procps,rename,resolvconf,rsyslog,ssh,sysstat,update-inetd" #libfile-fcntllock-perl,devscripts,
mirror_addr="http://httpredir.debian.org/debian/"
root_pw='1234'

# cleanup old
rm -rf "${rootfs}"
rm -rf "${target_dir}"/"${release}"-rootfs.tar.gz

# generate output directory
mkdir -p ${rootfs}

echo "### Creating build chroot: $release/$arch"

debootstrap --variant=minbase --arch="${arch}" --foreign --components="${components}" --include="${includes}" "${release}" "${rootfs}" "${mirror_addr}"
[[ $? -ne 0 || ! -f "${rootfs}"/debootstrap/debootstrap ]] && exit_with_error "### Create chroot first stage failed"

echo "### First stage completed"

cp /usr/bin/"${qemu_binary}" "${rootfs}"/usr/bin/

mkdir -p  "${rootfs}"/usr/share/keyrings/
cp /usr/share/keyrings/*-archive-keyring.gpg "${rootfs}"/usr/share/keyrings/

echo "### Copied qemu and keyring"

chroot "${rootfs}" /bin/bash -c "/debootstrap/debootstrap --second-stage"
[[ $? -ne 0 || ! -f "${rootfs}"/bin/bash ]] && exit_with_error "### Create chroot second stage failed"
echo "### Second stage completed"

echo "### Mounting / preparing chroot"
mount -t proc chproc "${rootfs}"/proc
mount -t sysfs chsys "${rootfs}"/sys
mount -t devtmpfs chdev "${rootfs}"/dev || mount --bind /dev "${rootfs}"/dev
mount -t devpts chpts "${rootfs}"/dev/pts


echo "### Applying tweaks"
[[ -f "${rootfs}"/etc/locale.gen ]] && sed -i "s/^# en_US.UTF-8/en_US.UTF-8/" "${rootfs}"/etc/locale.gen
chroot "${rootfs}" /bin/bash -c "locale-gen; update-locale LANG=en_US:en LC_ALL=en_US.UTF-8"
chroot "${rootfs}" /bin/bash -c "/usr/sbin/update-ccache-symlinks"

#if [[ -f "${rootfs}"/etc/default/console-setup ]]; then
#	sed -e 's/CHARMAP=.*/CHARMAP="UTF-8"/' -e 's/FONTSIZE=.*/FONTSIZE="8x16"/' \
#		-e 's/CODESET=.*/CODESET="guess"/' -i "${rootfs}"/etc/default/console-setup
#	eval 'LC_ALL=C LANG=C chroot $rootfs /bin/bash -c "setupcon --save"'
#fi

chroot "${rootfs}" /bin/bash -c "apt-get -y update"
chroot "${rootfs}" /bin/bash -c "apt-get -y full-upgrade"
chroot "${rootfs}" /bin/bash -c "apt-get -y autoremove"
chroot "${rootfs}" /bin/bash -c "apt-get -y clean"

# set root password
chroot "${rootfs}" /bin/bash -c "(echo ${root_pw};echo ${root_pw};) | passwd root >/dev/null 2>&1"

cat << EOF > ${rootfs}/etc/fstab
# Default mounts
/dev/sdb2       /               ext4    defaults,noatime,nodiratime,commit=600,errors=remount-ro 0 1
/dev/sdb1       /boot           auto    defaults                0       0

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

cat << EOF > ${rootfs}/etc/hostname
wdmycloud
EOF

cat << EOF > ${rootfs}/etc/network/interfaces
# interfaces(5) file used by ifup(8) and ifdown(8)
# Include files from /etc/network/interfaces.d:
source-directory /etc/network/interfaces.d

# loopback
iface lo inet loopback
iface lo inet6 loopback

# main network interface
auto eth0
allow-hotplug eth0
iface eth0 inet dhcp
#       address 192.168.1.7
#       netmask 255.255.255.0
#       gateway 192.168.1.1
#       dns-nameservers 192.168.1.1
EOF

echo "### Unmounting"
while grep -Eq "${rootfs}.*(dev|proc|sys)" /proc/mounts
do
	umount -l --recursive "${rootfs}"/dev >/dev/null 2>&1
	umount -l "${rootfs}"/proc >/dev/null 2>&1
	umount -l "${rootfs}"/sys >/dev/null 2>&1
	sleep 5
done

touch "${rootfs}"/root/.debootstrap-complete
echo "### Debootstrap complete: ${release}/${arch}"

cd "${rootfs}"

tar -czf ../"${release}"-rootfs.tar.gz .
