#!/bin/bash
# 平台检测 — 被其他脚本 source 使用
# 设置变量: HOST_OS, HOST_ARCH, QEMU_BIN, QEMU_MACHINE, QEMU_CPU,
#           QEMU_ACCEL, QEMU_CONSOLE, GDB_BIN, DOCKER_PLATFORM

detect_platform() {
    local os_name
    os_name=$(uname -s)

    case "$os_name" in
        Darwin) HOST_OS="macos" ;;
        Linux)  HOST_OS="linux" ;;
        MINGW*|MSYS*|CYGWIN*)
            echo "错误: Windows 请使用 WSL 运行此脚本"
            echo "  https://learn.microsoft.com/windows/wsl/install"
            exit 1
            ;;
        *) echo "错误: 不支持的操作系统: $os_name"; exit 1 ;;
    esac

    case "$(uname -m)" in
        x86_64)         HOST_ARCH="amd64" ;;
        aarch64|arm64)  HOST_ARCH="arm64" ;;
        *) echo "错误: 不支持的架构: $(uname -m)"; exit 1 ;;
    esac

    if [ "$HOST_ARCH" = "arm64" ]; then
        QEMU_BIN="qemu-system-aarch64"
        QEMU_MACHINE="-machine virt"
        QEMU_CPU="-cpu cortex-a57"
        QEMU_CONSOLE="ttyAMA0"
    else
        QEMU_BIN="qemu-system-x86_64"
        QEMU_MACHINE="-machine pc"
        QEMU_CPU="-cpu qemu64"
        QEMU_CONSOLE="ttyS0"
    fi

    QEMU_ACCEL=""
    if [ "$HOST_OS" = "linux" ] && [ -e /dev/kvm ]; then
        QEMU_ACCEL="-enable-kvm"
        QEMU_CPU="-cpu host"
    fi

    case "$HOST_OS" in
        macos)
            if [ "$HOST_ARCH" = "arm64" ]; then
                GDB_BIN="aarch64-elf-gdb"
            else
                GDB_BIN="x86_64-elf-gdb"
            fi
            ;;
        linux) GDB_BIN="gdb" ;;
    esac

    DOCKER_PLATFORM="linux/$HOST_ARCH"
}

check_port_ready() {
    if command -v lsof &>/dev/null; then
        lsof -i :1234 -sTCP:LISTEN >/dev/null 2>&1
    elif command -v ss &>/dev/null; then
        ss -tlnp 2>/dev/null | grep -q ':1234'
    else
        (echo > /dev/tcp/localhost/1234) 2>/dev/null
    fi
}
