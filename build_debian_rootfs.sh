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
# Adjust package list here
includes="ccache,locales,git,ca-certificates,debhelper,rsync,python3,distcc,systemd,init,udev,kmod,bash-completion,busybox,ethtool,dirmngr,hdparm,ifupdown,iproute2,iputils-ping,logrotate,net-tools,nftables,powermgmt-base,procps,rename,resolvconf,rsyslog,ssh,sysstat,update-inetd,isc-dhcp-client,isc-dhcp-common,vim,dialog,apt-utils,nano,keyboard-configuration,console-setup,linux-base" 
mirror_addr="http://httpredir.debian.org/debian/"

# Adjust default root pw
root_pw='1234'

# Adjust hostname here
def_hostname='wdmycloud'

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
#chroot "${rootfs}" /bin/bash -c "locale-gen; update-locale LANG=en_US:en LC_ALL=en_US.UTF-8"
chroot "${rootfs}" /bin/bash -c "dpkg-reconfigure locales"
chroot "${rootfs}" /bin/bash -c "dpkg-reconfigure tzdata"
chroot "${rootfs}" /bin/bash -c "dpkg-reconfigure keyboard-configuration"
chroot "${rootfs}" /bin/bash -c "/usr/sbin/update-ccache-symlinks"


chroot "${rootfs}" /bin/bash -c "apt-get -y update"
chroot "${rootfs}" /bin/bash -c "apt-get -y full-upgrade"
chroot "${rootfs}" /bin/bash -c "apt-get -y autoremove"
chroot "${rootfs}" /bin/bash -c "apt-get -y clean"

# set root password
chroot "${rootfs}" /bin/bash -c "(echo ${root_pw};echo ${root_pw};) | passwd root >/dev/null 2>&1"

# permit root login via SSH for the first boot
sed -i 's/#\?PermitRootLogin .*/PermitRootLogin yes/' "${rootfs}"/etc/ssh/sshd_config

# create fstab, adjust for your layout here
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

# Apply tweaks in sysctl
cat << EOF >> ${rootfs}/etc/sysctl.conf

vm.min_free_kbytes=8192
net.core.somaxconn=4096
net.core.wmem_max=16777216
net.core.rmem_max=16777216
net.core.wmem_default=163840
net.core.rmem_default=163840
net.core.netdev_max_backlog=3000
net.ipv4.tcp_keepalive_time=1800
net.ipv4.tcp_fin_timeout=30
net.ipv4.tcp_max_syn_backlog=2048
net.ipv4.tcp_timestamps=0
EOF

# Setup hostname
cat << EOF > ${rootfs}/etc/hostname
${def_hostname}
EOF

# Setup interfaces (eth0)
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
pre-up /sbin/ethtool -C eth0 pkt-rate-low 20000 pkt-rate-high 3000000 rx-frames 32 rx-usecs 1150 rx-usecs-high 1150 rx-usecs-low 100 rx-frames-low 32 rx-frames-high 32 adaptive-rx on
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
