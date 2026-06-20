#!/bin/bash
set -e

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

enable_config CONFIG_INITRAMFS_SOURCE
enable_config CONFIG_RD_GZIP
enable_config CONFIG_BLK_DEV_INITRD

enable_config CONFIG_PRINTK
enable_config CONFIG_CC_OPTIMIZE_FOR_SIZE

enable_config CONFIG_BINFMT_ELF
enable_config CONFIG_BINFMT_SCRIPT

enable_config CONFIG_BLK_DEV

enable_config CONFIG_DEVTMPFS
enable_config CONFIG_DEVTMPFS_MOUNT

enable_config CONFIG_TTY
enable_config CONFIG_SERIAL_8250 y
enable_config CONFIG_SERIAL_8250_CONSOLE y
enable_config CONFIG_SERIAL_AMBA_PL011 y
enable_config CONFIG_SERIAL_AMBA_PL011_CONSOLE y
enable_config CONFIG_HVC_DRIVER y
enable_config CONFIG_VIRTIO_CONSOLE y

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

enable_config CONFIG_OF y
enable_config CONFIG_ARCH_VIRT y

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

# 调试支持
enable_config CONFIG_DEBUG_INFO y
enable_config CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT y
enable_config CONFIG_GDB_SCRIPTS y
enable_config CONFIG_DEBUG_KERNEL y
enable_config CONFIG_FRAME_POINTER y
enable_config CONFIG_RANDOMIZE_BASE n

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
