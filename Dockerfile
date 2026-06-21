FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
    build-essential \
    bc \
    bison \
    flex \
    libelf-dev \
    libncurses-dev \
    libssl-dev \
    liburing-dev \
    cpio \
    gzip \
    git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

COPY init.c /build/init.c

RUN gcc -g -static init.c -o init -luring && \
    mkdir -p rootfs/dev rootfs/proc rootfs/sys && \
    cp init rootfs/init && \
    (cd rootfs && find . | cpio -o --format=newc | gzip -c > /build/initrd)

ARG CACHEBUST=1
RUN git clone --depth 1 https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git

WORKDIR /build/linux

ARG TARGETARCH
COPY kernel.config.sh /build/kernel.config.sh
RUN chmod +x /build/kernel.config.sh

RUN make tinyconfig && /build/kernel.config.sh "$TARGETARCH"

# 用 -O2 编译（内核需要 -O2 的常量折叠，-Og/-O1 会导致编译失败）
# 调试时建议在变量初始化后设断点，而不是函数入口
RUN make -j$(nproc)

RUN if [ "$(uname -m)" = "x86_64" ]; then \
        cp arch/x86/boot/bzImage /build/Image; \
    else \
        cp arch/arm64/boot/Image /build/Image; \
    fi && \
    cp vmlinux /build/vmlinux && \
    cp /build/init /build/init-debug