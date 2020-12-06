#!/bin/bash

cat << EOF > ${rootfs_dir}/etc/network/interfaces
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
#       dns-search fritz.box
pre-up /sbin/ethtool -C eth0 pkt-rate-low 20000 pkt-rate-high 3000000 rx-frames 32 rx-usecs 1150 rx-usecs-high 1150 rx-usecs-low 100 rx-frames-low 32 rx-frames-high 32 adaptive-rx on
EOF
