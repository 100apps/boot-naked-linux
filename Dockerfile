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
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

COPY init.c /build/init.c

RUN gcc -g -static init.c -o init && \
    mkdir -p rootfs/dev rootfs/proc rootfs/sys && \
    cp init rootfs/init && \
    (cd rootfs && find . | cpio -o --format=newc | gzip -c > /build/initrd)

ARG CACHEBUST=1
RUN git clone --depth 1 https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git

WORKDIR /build/linux

COPY kernel.config.sh /build/kernel.config.sh
RUN chmod +x /build/kernel.config.sh

RUN make tinyconfig && /build/kernel.config.sh

RUN make -j$(nproc)

RUN cp arch/arm64/boot/Image /build/Image && \
    cp vmlinux /build/vmlinux && \
    cp /build/init /build/init-debug
