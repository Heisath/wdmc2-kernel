#!/bin/bash

# we can never know what aliases may be set, so remove them all
unalias -a

# do preparation steps

# generate output directory
mkdir -p output/rootfs

debootstrap --variant=buildd --arch armhf --foreign stable output/rootfs http://httpredir.debian.org/debian/


