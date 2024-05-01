FROM docker.io/library/ubuntu:jammy as builder

RUN apt update && \
    apt upgrade -y && \
    apt install -y \
    git build-essential vim \
    bc dialog sudo \
    libncurses5 libncurses-dev libmpc-dev \
    libmpfr-dev libgmp3-dev \
    lib32z1 lib32ncurses5-dev \
    flex bison debootstrap debian-archive-keyring qemu-user-static \
    u-boot-tools kmod gcc-arm-none-eabi && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /build

VOLUME /build
