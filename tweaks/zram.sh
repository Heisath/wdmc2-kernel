#!/bin/bash

# These tweaks are borrowed from the ARMBIAN project. https://github.com/armbian/build
# Thanks for their awesome work.


cat << EOF > ${rootfs_dir}/etc/cron.daily/armbian-ram-logging
#!/bin/sh
/usr/lib/armbian/armbian-ramlog write >/dev/null 2>&1
EOF

cat << EOF > ${rootfs_dir}/etc/default/armbian-ramlog
# configuration values for the armbian-ram-logging service
#
# enable the armbian-ram-logging service?
ENABLED=true
#
# size of the tmpfs mount -- please keep in mind to adjust /etc/default/armbian-zram-config too when increasing
SIZE=50M
#
# use rsync instead of cp -r
# requires rsync installed, may provide better performance
# due to copying only new and changed files
USE_RSYNC=true
EOF

cat << EOF > ${rootfs_dir}/etc/default/armbian-zram-config
# configuration values for the armbian-zram-config service
#
# enable the armbian-zram-config service?
ENABLED=true

# percentage of zram used as swap compared to physically available DRAM.
# Huge overcommitment (300) is possible and sometimes desirable. See
# https://forum.armbian.com/topic/5565-zram-vs-swap/?do=findComment&comment=61082
# and don't forget to adjust $MEM_LIMIT_PERCENTAGE below too.
# ZRAM_PERCENTAGE=50

# percentage of DRAM available to zram. If this amount is exceeded the zram
# devices used for swap simply behave as if the device is full. You need to
# adjust/increase this value only if you want to work with massive memory
# overcommitment (ZRAM_PERCENTAGE exceeding 150 for example)
# MEM_LIMIT_PERCENTAGE=50

# create how many zram devices max for swap
# ZRAM_MAX_DEVICES=4

# Which algorithm for zram based swapping. Seems lzo is best choice on ARM:
# https://forum.armbian.com/topic/8161-swap-on-sbc/?do=findComment&comment=61668
# SWAP_ALGORITHM=lzo

# Which algorithm to choose for zram based ramlog partition
# RAMLOG_ALGORITHM=zstd

# Which algorithm to choose for zram based /tmp
# TMP_ALGORITHM=zstd

# If defined a separate partition will be used as zram backing device. Be CAREFUL
# which partition you assign and read starting from CONFIG_ZRAM_WRITEBACK in
# https://www.kernel.org/doc/Documentation/blockdev/zram.txt
# ZRAM_BACKING_DEV=/dev/nvme0n2
EOF

cat << EOF > ${rootfs_dir}/lib/systemd/system/armbian-ramlog.service
# Armbian ramlog service
# Stores logs in (compressed) memory
# This service may block the boot process for up to 30 sec

[Unit]
Description=Armbian memory supported logging
DefaultDependencies=no
Before=rsyslog.service sysinit.target syslog.target
After=armbian-zram-config.service
Conflicts=shutdown.target
RequiresMountsFor=/var/log /var/log.hdd
IgnoreOnIsolate=yes

[Service]
Type=oneshot
ExecStart=/usr/lib/armbian/armbian-ramlog start
ExecStop=/usr/lib/armbian/armbian-ramlog stop
ExecReload=/usr/lib/armbian/armbian-ramlog write
RemainAfterExit=yes
TimeoutStartSec=30sec

[Install]
WantedBy=sysinit.target
EOF

cat << EOF > ${rootfs_dir}/lib/systemd/system/armbian-zram-config.service
# Armbian ZRAM configuration service
# Create 1 + number of cores compressed block devices
# This service may block the boot process for up to 30 sec

[Unit]
Description=Armbian ZRAM config
DefaultDependencies=no
After=local-fs.target
Before=armbian-ramlog.target
Conflicts=shutdown.target

[Service]
Type=oneshot
ExecStart=/usr/lib/armbian/armbian-zram-config start
ExecStop=/usr/lib/armbian/armbian-zram-config stop
RemainAfterExit=yes
TimeoutStartSec=30sec

[Install]
WantedBy=sysinit.target
EOF

mkdir ${rootfs_dir}/usr/lib/armbian

cat << EOF > ${rootfs_dir}/usr/lib/armbian/armbian-ramlog
#!/bin/bash
#
# Copyright (c) Authors: http://www.armbian.com/authors
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

SIZE=50M
USE_RSYNC=true
ENABLED=false

[ -f /etc/default/armbian-ramlog ] && . /etc/default/armbian-ramlog

[ "\$ENABLED" != true ] && exit 0

# Never touch anything below here. Only edit /etc/default/armbian-ramlog

HDD_LOG=/var/log.hdd/
RAM_LOG=/var/log/
LOG2RAM_LOG="\${HDD_LOG}armbian-ramlog.log"
LOG_OUTPUT="tee -a \$LOG2RAM_LOG"

isSafe () {
	[ -d \$HDD_LOG ] || (echo "ERROR: \$HDD_LOG doesn't exist! Can't sync." >&2 ; exit 1)
	NoCache=\$(which nocache 2>/dev/null)
}

RecreateLogs (){
	# in case of crash those services don't start if there are no dirs & logs
	check_if_installed apache2 && [ ! -d /var/log/apache2 ] && mkdir -p /var/log/apache2
	check_if_installed cron-apt && [ ! -d /var/log/cron-apt ] && \
		(mkdir -p /var/log/cron-apt ; touch /var/log/cron-apt/log)
	check_if_installed proftpd-basic && [ ! -d /var/log/proftpd ] && \
		(mkdir -p /var/log/proftpd ; touch /var/log/proftpd/controls.log)
	check_if_installed nginx && [ ! -d /var/log/nginx ] && \
		(mkdir -p /var/log/nginx ; touch /var/log/nginx/access.log ; touch /var/log/nginx/error.log)
	check_if_installed samba && [ ! -d /var/log/samba ] && mkdir -p /var/log/samba
	check_if_installed unattended-upgrades && [ ! -d /var/log/unattended-upgrades ] && mkdir -p /var/log/unattended-upgrades
	return 0
}

syncToDisk () {
	isSafe

	echo -e "\n\n\$(date): Syncing logs from \$LOG_TYPE to storage\n" | \$LOG_OUTPUT

	if [ "\$USE_RSYNC" = true ]; then
		\${NoCache} rsync -aXWv --delete --exclude "lost+found" --exclude armbian-ramlog.log --links \$RAM_LOG \$HDD_LOG 2>&1 | \$LOG_OUTPUT
	else
		\${NoCache} cp -rfup \$RAM_LOG -T \$HDD_LOG 2>&1 | \$LOG_OUTPUT
	fi

	sync
}

syncFromDisk () {
	isSafe

	echo -e "\n\n\$(date): Loading logs from storage to \$LOG_TYPE\n" | \$LOG_OUTPUT

	if [ "\$USE_RSYNC" = true ]; then
		\${NoCache} rsync -aXWv --delete --exclude "lost+found" --exclude armbian-ramlog.log --exclude *.gz --exclude='*.[0-9]' --links \$HDD_LOG \$RAM_LOG 2>&1 | \$LOG_OUTPUT
	else
		\${NoCache} find \$HDD_LOG* -maxdepth 1 -type f -not \( -name '*.[0-9]' -or -name '*.xz*' -or -name '*.gz' \) | xargs cp -ut \$RAM_LOG
	fi

	sync
}

check_if_installed () {
	local DPKG_Status="\$(dpkg -s "\$1" 2>/dev/null | awk -F": " '/^Status/ {print \$2}')"
	if [[ "X\${DPKG_Status}" = "X" || "\${DPKG_Status}" = *deinstall* ]]; then
		return 1
	else
		return 0
	fi
}

# Check whether zram device is available or we need to use tmpfs
if [ "\$(blkid -s TYPE /dev/zram0 | awk ' { print \$2 } ' | grep ext4)" ]; then
	LOG_TYPE="zram"
else
	LOG_TYPE="tmpfs"
fi

case "\$1" in
	start)
		[ -d \$HDD_LOG ] || mkdir -p \$HDD_LOG
		mount --bind \$RAM_LOG \$HDD_LOG
		mount --make-private \$HDD_LOG

		case \$LOG_TYPE in
			zram)
				echo -e "Mounting /dev/zram0 as \$RAM_LOG \c" | \$LOG_OUTPUT
				mount -o discard /dev/zram0 \$RAM_LOG 2>&1 | \$LOG_OUTPUT
				;;
			tmpfs)
				echo -e "Setting up \$RAM_LOG as tmpfs \c" | \$LOG_OUTPUT
				mount -t tmpfs -o nosuid,noexec,nodev,mode=0755,size=\$SIZE armbian-ramlog \$RAM_LOG 2>&1 | \$LOG_OUTPUT
				;;
		esac

		syncFromDisk
		RecreateLogs
		;;
	stop)
		syncToDisk
		umount -l \$RAM_LOG
		umount -l \$HDD_LOG
		;;
	write)
		syncToDisk
		;;
	*)
		echo "Usage: \${0##*/} {start|stop|write}" >&2
		exit 1
		;;
esac
EOF

cat << EOF > ${rootfs_dir}/usr/lib/armbian/armbian-zram-config
#!/bin/bash
#
# Copyright (c) Authors: http://www.armbian.com/authors
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# Functions:
#
# activate_zram_swap
# activate_ramlog_partition
# activate_compressed_tmp


# Read in basic OS image information
#. /etc/armbian-release
# and script configuration
#. /usr/lib/armbian/armbian-common

Log=/var/log/armbian-zram.log

# It's possible to override ZRAM_PERCENTAGE, ZRAM_MAX_DEVICES, SWAP_ALGORITHM,
# RAMLOG_ALGORITHM and TMP_ALGORITHM here:
[ -f /etc/default/armbian-zram-config ] && . /etc/default/armbian-zram-config

activate_zram_swap() {
	# Do not interfere with already present config-zram package
	dpkg -l | grep -q 'zram-config' && exit 0

	[[ "\$ENABLED" != "true" ]] && exit 0

	# Load zram module with n instances for swap: one per CPU core, $ZRAM_MAX_DEVICES
	# defines the maximum, on modern kernels we overwrite this with 1 and rely on
	# max_comp_streams being set to count of CPU cores or $ZRAM_MAX_DEVICES
	uname -r | grep -q '^3.' && zram_max_devs=\${ZRAM_MAX_DEVICES:=4} || zram_max_devs=1
	cpu_cores=\$(grep -c '^processor' /proc/cpuinfo | sed 's/^0\$/1/')
	[[ \${cpu_cores} -gt \${zram_max_devs} ]] && zram_devices=\${zram_max_devs} || zram_devices=\${cpu_cores}
	module_args="\$(modinfo zram | awk -F" " '/num_devices/ {print \$2}' | cut -f1 -d:)"
	[[ -n \${module_args} ]] && modprobe zram \${module_args}=\$(( \${zram_devices} + 2 )) || return

	# Expose 50% of real memory as swap space by default
	zram_percent=\${ZRAM_PERCENTAGE:=50}
	mem_info=\$(LC_ALL=C free -w 2>/dev/null | grep "^Mem" || LC_ALL=C free | grep "^Mem")
	memory_total=\$(awk '{printf("%d",\$2*1024)}' <<<\${mem_info})
	mem_per_zram_device=\$(( \${memory_total} / \${zram_devices} * \${zram_percent} / 100 ))

	# Limit memory available to zram to 50% by default
	mem_limit_percent=\${MEM_LIMIT_PERCENTAGE:=50}
	mem_limit_per_zram_device=\$(( \${memory_total} / \${zram_devices} * \${mem_limit_percent} / 100 ))

	swap_algo=\${SWAP_ALGORITHM:=lzo}
	for (( i=1; i<=zram_devices; i++ )); do
		[[ -f /sys/block/zram\${i}/comp_algorithm ]] && echo \${swap_algo} >/sys/block/zram\${i}/comp_algorithm 2>/dev/null
		if [ "X\${ZRAM_BACKING_DEV}" != "X" ]; then
			echo \${ZRAM_BACKING_DEV} >/sys/block/zram\${i}/backing_dev
		fi
		echo -n \${ZRAM_MAX_DEVICES:=4} > /sys/block/zram\${i}/max_comp_streams
		echo -n \${mem_per_zram_device} > /sys/block/zram\${i}/disksize
		echo -n \${mem_limit_per_zram_device} > /sys/block/zram\${i}/mem_limit
		mkswap /dev/zram\${i}
		swapon -p 5 /dev/zram\${i}
	done

	# Swapping to HDDs is stupid so switch to settings made for flash memory and zram/zswap
	echo 0 > /proc/sys/vm/page-cluster

	echo -e "\n### Activated \${zram_devices} \${swap_algo} zram swap devices with \$(( \${mem_per_zram_device} / 1048576 )) MB each\n" >>\${Log}
} # activate_zram_swap

activate_ramlog_partition() {
	# /dev/zram0 will be used as a compressed /var/log partition in RAM if
	# ENABLED=true in /etc/default/armbian-ramlog is set
	ENABLED=\$(awk -F"=" '/^ENABLED/ {print \$2}' /etc/default/armbian-ramlog)
	[[ "\$ENABLED" != "true" ]] && return
	
	# read size also from /etc/default/armbian-ramlog
	ramlogsize=\$(awk -F"=" '/^SIZE/ {print \$2}' /etc/default/armbian-ramlog)
	disksize=\$(sed -e 's/M\$/*1048576/' -e 's/K\$/*1024/' <<<\${ramlogsize:=50M} | bc)

	# choose RAMLOG_ALGORITHM if defined in /etc/default/armbian-zram-config
	# otherwise try to choose most efficient compression scheme available.
	# See https://patchwork.kernel.org/patch/9918897/
	if [ "X\${RAMLOG_ALGORITHM}" = "X" ]; then
		for algo in lz4 lz4hc quicklz zlib brotli zstd ; do
			echo \${algo} >/sys/block/zram0/comp_algorithm 2>/dev/null
		done
	else
		echo \${RAMLOG_ALGORITHM} >/sys/block/zram0/comp_algorithm 2>/dev/null
	fi
	echo -n \${disksize} > /sys/block/zram0/disksize

	# if it fails, select \$swap_algo. Workaround for some older kernels
	if [[ \$? == 1 ]]; then
		echo \${swap_algo} > /sys/block/zram0/comp_algorithm 2>/dev/null
		echo -n \${disksize} > /sys/block/zram0/disksize
	fi

	mkfs.ext4 -O ^has_journal -s 1024 -L log2ram /dev/zram0
	algo=\$(sed 's/.*\[\([^]]*\)\].*/\1/g' </sys/block/zram0/comp_algorithm)
	echo -e "### Activated Armbian ramlog partition with \${algo} compression" >>\${Log}
} # activate_ramlog_partition

activate_compressed_tmp() {
	# create /tmp not as tmpfs but zram compressed if no fstab entry exists
	grep -q '/tmp' /etc/fstab && return

	tmp_device=\$(( \${zram_devices} + 1 ))
	if [[ -f /sys/block/zram\${tmp_device}/comp_algorithm ]]; then
		if [ "X\${TMP_ALGORITHM}" = "X" ]; then
			echo \${swap_algo} >/sys/block/zram\${tmp_device}/comp_algorithm 2>/dev/null
		else
			echo \${TMP_ALGORITHM} >/sys/block/zram\${tmp_device}/comp_algorithm 2>/dev/null
		fi
	fi
	echo -n \$(( \${memory_total} / 2 )) > /sys/block/zram\${tmp_device}/disksize
	mkfs.ext4 -O ^has_journal -s 1024 -L tmp /dev/zram\${tmp_device}
	mount -o nosuid,discard /dev/zram\${tmp_device} /tmp
	chmod 777 /tmp
	algo=\$(sed 's/.*\[\([^]]*\)\].*/\1/g' </sys/block/zram\${tmp_device}/comp_algorithm)
	echo -e "\n### Activated \${algo} compressed /tmp" >>\${Log}
} # activate_compressed_tmp

case \$1 in
	*start*)
		activate_zram_swap
		activate_ramlog_partition
		activate_compressed_tmp
		;;
esac
EOF

chmod +x ${rootfs_dir}/etc/cron.daily/armbian-ram-logging
chmod +x ${rootfs_dir}/usr/lib/armbian/armbian-ramlog
chmod +x ${rootfs_dir}/usr/lib/armbian/armbian-zram-config

chroot ${rootfs_dir} systemctl enable armbian-zram-config.service
chroot ${rootfs_dir} systemctl enable armbian-ramlog.service

