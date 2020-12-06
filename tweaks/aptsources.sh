#!/bin/bash

cat << EOF > ${rootfs_dir}/etc/apt/sources.list
###
deb http://httpredir.debian.org/debian ${release} main contrib non-free
deb-src http://httpredir.debian.org/debian ${release} main contrib non-free

deb http://httpredir.debian.org/debian-security/ ${release}/updates main contrib non-free
deb-src http://httpredir.debian.org/debian-security/ ${release}/updates main contrib non-free

deb http://httpredir.debian.org/debian ${release}-updates main contrib non-free
deb-src http://httpredir.debian.org/debian ${release}-updates main contrib non-free

deb http://httpredir.debian.org/debian ${release}-backports main contrib non-free
deb-src http://httpredir.debian.org/debian ${release}-backports main contrib non-free
###
EOF
