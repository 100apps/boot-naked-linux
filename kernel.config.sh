#!/bin/bash
set -e

TARGETARCH="${1:-$(uname -m)}"

case "$TARGETARCH" in
    arm64|aarch64) TARGETARCH="arm64" ;;
    amd64|x86_64)  TARGETARCH="amd64" ;;
esac

CONFIG=".config"

enable_config() {
    local key=$1
    local val=${2:-y}
    if grep -q "# $key is not set" "$CONFIG" 2>/dev/null; then
        sed -i "s/# $key is not set/$key=$val/" "$CONFIG"
    elif grep -q "^$key=" "$CONFIG" 2>/dev/null; then
        sed -i "s/^$key=.*/$key=$val/" "$CONFIG"
    else
        echo "$key=$val" >> "$CONFIG"
    fi
}

# === 公共配置 ===

enable_config CONFIG_INITRAMFS_SOURCE
enable_config CONFIG_RD_GZIP
enable_config CONFIG_BLK_DEV_INITRD

enable_config CONFIG_PRINTK
# 保持 -O2 编译（arm64 用 -Og/-O1 会导致 BUILD_BUG_ON 编译失败）
# 调试时请在变量初始化之后的代码行设置断点，而非函数入口

enable_config CONFIG_BINFMT_ELF
enable_config CONFIG_BINFMT_SCRIPT

enable_config CONFIG_BLK_DEV

enable_config CONFIG_DEVTMPFS
enable_config CONFIG_DEVTMPFS_MOUNT

enable_config CONFIG_TTY
enable_config CONFIG_SERIAL_CORE y
enable_config CONFIG_SERIAL_CORE_CONSOLE y
enable_config CONFIG_VT y
enable_config CONFIG_CONSOLE_TRANSLATIONS y
enable_config CONFIG_VT_CONSOLE y

enable_config CONFIG_VIRTIO y
enable_config CONFIG_VIRTIO_MMIO y
enable_config CONFIG_VIRTIO_PCI y
enable_config CONFIG_PCI y
enable_config CONFIG_PCI_HOST_GENERIC y

enable_config CONFIG_HVC_DRIVER y
enable_config CONFIG_VIRTIO_CONSOLE y

enable_config CONFIG_SMP
enable_config CONFIG_NR_CPUS 4

# 网络栈
enable_config CONFIG_NET y
enable_config CONFIG_INET y
enable_config CONFIG_TCP_CONG_CUBIC y
enable_config CONFIG_DEFAULT_TCP_CONG '"cubic"'
enable_config CONFIG_PACKET y
enable_config CONFIG_UNIX y
enable_config CONFIG_NETDEVICES y
enable_config CONFIG_NET_CORE y
enable_config CONFIG_ETHERNET y
enable_config CONFIG_VIRTIO_NET y

# proc/sysfs（网络栈依赖）
enable_config CONFIG_PROC_FS y
enable_config CONFIG_PROC_SYSCTL y
enable_config CONFIG_SYSFS y

# epoll / select / eventfd（I/O 多路复用）
enable_config CONFIG_EPOLL y
enable_config CONFIG_EVENTFD y

# io_uring（异步 I/O）
enable_config CONFIG_IO_URING y

# 调试支持
enable_config CONFIG_DEBUG_INFO y
enable_config CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT y
enable_config CONFIG_GDB_SCRIPTS y
enable_config CONFIG_DEBUG_KERNEL y
enable_config CONFIG_FRAME_POINTER y
enable_config CONFIG_RANDOMIZE_BASE n
enable_config CONFIG_KALLSYMS y
enable_config CONFIG_KALLSYMS_ALL y

# === 架构特定配置 ===

if [ "$TARGETARCH" = "arm64" ]; then
    enable_config CONFIG_SERIAL_AMBA_PL011 y
    enable_config CONFIG_SERIAL_AMBA_PL011_CONSOLE y
    enable_config CONFIG_SERIAL_8250 y
    enable_config CONFIG_SERIAL_8250_CONSOLE y
    enable_config CONFIG_OF y
    enable_config CONFIG_ARCH_VIRT y
else
    enable_config CONFIG_SERIAL_8250 y
    enable_config CONFIG_SERIAL_8250_CONSOLE y
    enable_config CONFIG_IA32_EMULATION n
    enable_config CONFIG_64BIT y
fi

make olddefconfig

# olddefconfig 可能因依赖关系关掉某些选项，再确认一次
enable_config CONFIG_VIRTIO y
enable_config CONFIG_VIRTIO_MENU y
enable_config CONFIG_VIRTIO_PCI y
enable_config CONFIG_VIRTIO_PCI_MODERN y
enable_config CONFIG_VIRTIO_MMIO y
enable_config CONFIG_VIRTIO_RING y
enable_config CONFIG_NETDEVICES y
enable_config CONFIG_ETHERNET y
enable_config CONFIG_NET_CORE y
enable_config CONFIG_VIRTIO_NET y
make olddefconfig
