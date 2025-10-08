#!/bin/bash
# set -x
# https://wiki.gentoo.org/wiki/Custom_Initramfs

# needed to make parsing outputs more reliable
export LC_ALL=C
# we can never know what aliases may be set, so remove them all
unalias -a

# destination
CURRENT_DIR=$PWD
INITRAMFS=${CURRENT_DIR}/initramfs
INITRAMFS_ROOT="${INITRAMFS}"/root

if [ "$1" = '--update' ]
then
  UPDATE_BOOT='yes'
else
  UPDATE_BOOT='no'
fi

echo '### Removing old stuff'

# remove old cruft
rm -rf "${INITRAMFS:?}"

mkdir -p "${INITRAMFS}"
mkdir -p "${INITRAMFS_ROOT}"

echo '### Creating initramfs root'

mkdir -p "${INITRAMFS_ROOT}"/{bin,etc,lib,lib64,newroot,proc,sbin,sys,usr} \
  "${INITRAMFS_ROOT}"/usr/{bin,sbin} \
  "${INITRAMFS_ROOT}"/dev/pts
cp -a /dev/{null,console,tty} "${INITRAMFS_ROOT}"/dev

add_bin(){
  BIN=${1:-}
  BIN_PATH=$(which "$BIN") || return 1
  BIN_DEST=${2:-$BIN_PATH}

  cp -a "${BIN_PATH}" "${INITRAMFS_ROOT}/${BIN_DEST}"
  ldd "${BIN_PATH}" > /dev/null 2>&1 && \
    cp $(ldd "${BIN_PATH}" | grep -o -E '/.* ') "${INITRAMFS_ROOT}/lib/"

  return 0
}

add_bin busybox /bin/busybox
add_bin e2fsck /sbin/e2fsck
add_bin fdisk /sbin/fdisk

cat << EOF > "${INITRAMFS_ROOT:?}"/init
#!/bin/busybox sh
# set -x

PATH=bin:sbin:usr/bin:usr/sbin

/bin/busybox --install

rescue_shell(){
  wd_set_led blue
  rescue_telnet

  printf '\e[1;31m' # bold red foreground
  printf "\$1 - dropping to a shell."
  printf "\e[00m\n" # normal color foreground
  # exec setsid cttyhack /bin/busybox sh
  exec /bin/busybox sh
}

rescue_telnet(){
  [ -x /usr/sbin/telnetd ] || return 1

  init_mount
  mount -t devpts none /dev/pts

  ip link set eth0 up
  ip addr add 192.168.1.1/24 dev eth0
  # udhcpc -n -q -i eth0  -x hostname:rescue-wd

  telnetd -l /bin/sh -b 0.0.0.0:6666
  sleep 30
}

ask_for_stop(){
  key='boot'
  read -r -p "### Press any key in 5s to stop and run shell..." -n1 -t5 key
  if [ \$key != 'boot' ]; then
    rescue_shell
  fi
}

try_boot(){
  device=\${1:-/dev/sdb2}

  if [ ! -x /newroot/\${init} ] && [ ! -h /newroot/\${init} ] && [ -b \${device} ]; then
    mount -t \${rootfstype} -o \${ro},\${rootflags} \${device} /newroot
    if [ ! -x /newroot/\${init} ] && [ ! -h /newroot/\${init} ]; then
      umount \${device}
    fi
  fi
}

wd_set_mac(){
  mac=\$(dd if=/dev/mtd0ro bs=1 skip=1046528 count=17 2>/dev/null)
  ip link set dev eth0 address \${mac:-00:90:A9:00:DE:AD}
}

wd_set_led(){
  led_color=\${1:-green}
  echo none > /sys/class/leds/system-blue/trigger
  echo ide-disk > /sys/class/leds/system-red/trigger
  echo default-on > /sys/class/leds/system-\${led_color}/trigger
}

init_mount(){
  mount -t devtmpfs none /dev
  mount -t proc none /proc
  mount -t sysfs none /sys
}

init_mount
ask_for_stop
sleep 5

# set mac from nand
wd_set_mac

# get cmdline parameters
init="/sbin/init"
root=\$1
rootflags=
rootfstype=auto
ro="ro"

for param in \$(cat /proc/cmdline); do
  case \$param in
    init=*)         init=\${param#init=};;
    root=*)         root=\${param#root=};;
    rootfstype=*)   rootfstype=\${param#rootfstype=};;
    rootflags=*)    rootflags=\${param#rootflags=};;
    ro)             ro="ro";;
    rw)             ro="rw";;
  esac
done

# try to mount the root filesystem.
if [ "\${root}"x != "/dev/ram"x ]; then
  mount -t \${rootfstype} -o \${ro},\${rootflags} \${root} /newroot || rescue_shell "mount \${root} failed."
fi

# try 2nd partition on usb
try_boot /dev/sdb2

# try 1st partition on hdd
try_boot /dev/sda1

# try 3rd partition on hdd
try_boot /dev/sda3 || rescue_shell "nothing bootable"

# turn led green
wd_set_led green

# clean up
umount /dev/pts /dev /sys /proc
killall telnetd

# boot the new root
exec switch_root /newroot \${init}

rescue_shell "end reached"
EOF

chmod +x "${INITRAMFS_ROOT}/init"

echo '### Creating uRamdisk'

cd "${INITRAMFS_ROOT}" || return
find . -print | cpio -ov --format=newc | gzip -9 > "${INITRAMFS}"/custom-initramfs.cpio.gz
mkimage -A arm -O linux -T ramdisk -a 0x00e00000 -e 0x0 -n "mycloud initramfs" -d "${INITRAMFS}"/custom-initramfs.cpio.gz "${INITRAMFS}"/uRamdisk

if [ "$UPDATE_BOOT" = 'yes' ]; then
  if [ -e '/boot/boot/' ]; then
    echo '### Updating /boot/boot'

    if [ -e '/boot/boot/uRamdisk' ]; then
      mv /boot/boot/uRamdisk /boot/boot/uRamdisk.old
    fi

    mv "${INITRAMFS}"/uRamdisk /boot/boot/uRamdisk
  elif [ -e '/boot/' ]; then
    echo '### Updating /boot'

    if [ -e '/boot/uRamdisk' ]; then
      mv /boot/uRamdisk /boot/uRamdisk.old
    fi

    mv "${INITRAMFS}"/uRamdisk /boot/uRamdisk
  fi

  rm -rf "${INITRAMFS}"
else
  echo '### Cleanup'
  rm -rf "${INITRAMFS}"/custom-initramfs.cpio.gz
  rm -rf "${INITRAMFS_ROOT:?}"
fi

echo '### Done.'
