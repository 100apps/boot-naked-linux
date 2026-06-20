FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
    build-essential \
    bc \
    bison \
    flex \
    libelf-dev \
    libncurses-dev \
    libssl-dev \
    cpio \
    gzip \
    git \
    wget \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

COPY init.c /build/init.c

RUN gcc -g -static init.c -o init && \
    echo 'init' | cpio -o --format=newc | gzip -c > initrd

ARG KERNEL_VERSION=6.12.8
RUN wget -q https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${KERNEL_VERSION}.tar.xz && \
    tar xf linux-${KERNEL_VERSION}.tar.xz && \
    mv linux-${KERNEL_VERSION} linux && \
    rm linux-${KERNEL_VERSION}.tar.xz

WORKDIR /build/linux

COPY kernel.config.sh /build/kernel.config.sh
RUN chmod +x /build/kernel.config.sh

RUN make tinyconfig && /build/kernel.config.sh

RUN make -j$(nproc)

RUN cp arch/arm64/boot/Image /build/Image && \
    cp vmlinux /build/vmlinux && \
    cp /build/init /build/init-debug
