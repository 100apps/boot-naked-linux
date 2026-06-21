#!/bin/bash
#
# boot-naked-linux.sh — 一键构建最小 Linux 内核
#
# 用法:
#   ./boot-naked-linux.sh          构建 + 启动
#   ./boot-naked-linux.sh build    仅构建
#   ./boot-naked-linux.sh run      仅启动（需要先构建）
#   ./boot-naked-linux.sh debug    启动 QEMU 调试模式（等待 GDB 连接）
#
# 支持平台: macOS (arm64/x86_64), Linux (arm64/x86_64), Windows (via WSL)
# 前置条件: Docker + QEMU
# 参考: https://nick.zoic.org/art/boot-naked-linux/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/scripts/platform.sh"
detect_platform

# ----------------------------------------------------------------
# 依赖检查
# ----------------------------------------------------------------

install_qemu() {
    echo "正在安装 QEMU ..."
    case "$HOST_OS" in
        macos)  brew install qemu ;;
        linux)
            if command -v apt-get &>/dev/null; then
                sudo apt-get update && sudo apt-get install -y qemu-system
            elif command -v dnf &>/dev/null; then
                sudo dnf install -y qemu-system-aarch64 qemu-system-x86
            elif command -v pacman &>/dev/null; then
                sudo pacman -S --noconfirm qemu-full
            else
                echo "错误: 无法自动安装 QEMU，请手动安装 $QEMU_BIN"
                exit 1
            fi
            ;;
    esac
}

check_deps() {
    if ! command -v docker &>/dev/null; then
        echo "错误: 未找到 docker，请先安装 Docker"
        echo "  macOS:   https://www.docker.com/products/docker-desktop/"
        echo "  Linux:   https://docs.docker.com/engine/install/"
        echo "  Windows: 请使用 WSL + Docker Desktop"
        exit 1
    fi

    if ! docker info &>/dev/null 2>&1; then
        echo "错误: Docker 未运行，请先启动 Docker"
        exit 1
    fi

    if ! command -v "$QEMU_BIN" &>/dev/null; then
        install_qemu
    fi
}

check_debug_deps() {
    if ! command -v "$GDB_BIN" &>/dev/null; then
        echo "正在安装 GDB ..."
        case "$HOST_OS" in
            macos)
                if [ "$HOST_ARCH" = "arm64" ]; then
                    brew install aarch64-elf-gdb
                else
                    brew install x86_64-elf-gdb
                fi
                ;;
            linux)
                if command -v apt-get &>/dev/null; then
                    sudo apt-get update && sudo apt-get install -y gdb
                elif command -v dnf &>/dev/null; then
                    sudo dnf install -y gdb
                elif command -v pacman &>/dev/null; then
                    sudo pacman -S --noconfirm gdb
                fi
                ;;
        esac
    fi
}

# ----------------------------------------------------------------
# 构建
# ----------------------------------------------------------------

do_build() {
    check_deps

    echo "=== Boot Naked Linux Builder ==="
    echo "内核版本: mainline latest"
    echo "目标架构: $HOST_ARCH"
    echo ""

    echo "[1/3] 使用 Docker 编译内核（首次约 5-10 分钟）..."
    docker build --platform "$DOCKER_PLATFORM" \
        --build-arg CACHEBUST="$(date +%s)" \
        --build-arg TARGETARCH="$HOST_ARCH" \
        -t boot-naked-linux "$SCRIPT_DIR"

    echo ""
    echo "[2/3] 提取构建产物..."
    CONTAINER_ID=$(docker create boot-naked-linux)
    docker cp "$CONTAINER_ID:/build/Image"  "$SCRIPT_DIR/Image"
    docker cp "$CONTAINER_ID:/build/initrd" "$SCRIPT_DIR/initrd"
    docker cp "$CONTAINER_ID:/build/vmlinux" "$SCRIPT_DIR/vmlinux"
    docker cp "$CONTAINER_ID:/build/init-debug" "$SCRIPT_DIR/init-debug"
    docker rm "$CONTAINER_ID" >/dev/null

    echo "  Image:   $(du -h "$SCRIPT_DIR/Image"   | cut -f1)  (内核)"
    echo "  vmlinux: $(du -h "$SCRIPT_DIR/vmlinux" | cut -f1)  (调试符号)"
    echo "  initrd:  $(du -h "$SCRIPT_DIR/initrd"  | cut -f1)  (init 程序)"

    echo ""
    echo "[3/3] 提取内核源码（调试用）..."
    if [ -d "$SCRIPT_DIR/linux-src" ]; then
        echo "  linux-src/ 已存在，跳过（如需更新请先删除）"
    else
        CONTAINER_ID=$(docker create boot-naked-linux)
        docker cp "$CONTAINER_ID:/build/linux/." "$SCRIPT_DIR/linux-src"
        docker rm "$CONTAINER_ID" >/dev/null
        echo "  已提取到 linux-src/"
    fi

    echo ""
    echo "构建完成！"
}

# ----------------------------------------------------------------
# 运行
# ----------------------------------------------------------------

do_run() {
    if [ ! -f "$SCRIPT_DIR/Image" ] || [ ! -f "$SCRIPT_DIR/initrd" ]; then
        echo "错误: 未找到 Image 或 initrd，请先运行: $0 build"
        exit 1
    fi

    check_deps

    echo "=== 启动最小 Linux ($HOST_ARCH) ==="
    $QEMU_BIN \
        $QEMU_MACHINE \
        $QEMU_CPU \
        $QEMU_ACCEL \
        -m 256M \
        -nographic \
        -kernel "$SCRIPT_DIR/Image" \
        -initrd "$SCRIPT_DIR/initrd" \
        -append "console=$QEMU_CONSOLE" \
        -no-reboot \
        -netdev user,id=net0 \
        -device virtio-net-pci,netdev=net0
}

# ----------------------------------------------------------------
# 调试模式
# ----------------------------------------------------------------

do_debug() {
    if [ ! -f "$SCRIPT_DIR/Image" ] || [ ! -f "$SCRIPT_DIR/vmlinux" ]; then
        echo "错误: 未找到 Image 或 vmlinux，请先运行: $0 build"
        exit 1
    fi

    check_deps
    check_debug_deps

    echo "=== 启动 QEMU 调试模式 ($HOST_ARCH) ==="
    echo "QEMU 已暂停，等待 GDB 连接到 localhost:1234"
    echo ""
    echo "连接方式："
    echo "  方式 1: VSCode 按 F5 选择 \"Debug Linux Kernel (Attach)\""
    echo "  方式 2: $GDB_BIN vmlinux -ex 'target remote :1234'"
    echo ""

    $QEMU_BIN \
        $QEMU_MACHINE \
        $QEMU_CPU \
        $QEMU_ACCEL \
        -m 256M \
        -nographic \
        -kernel "$SCRIPT_DIR/Image" \
        -initrd "$SCRIPT_DIR/initrd" \
        -append "console=$QEMU_CONSOLE nokaslr" \
        -no-reboot \
        -netdev user,id=net0 \
        -device virtio-net-pci,netdev=net0 \
        -S -gdb tcp::1234
}

# ----------------------------------------------------------------
# 入口
# ----------------------------------------------------------------

case "${1:-}" in
    build)
        do_build
        ;;
    run)
        do_run
        ;;
    debug)
        do_debug
        ;;
    "")
        do_build
        echo ""
        do_run
        ;;
    *)
        echo "用法: $0 [build|run|debug]"
        echo ""
        echo "  build   构建内核（Docker）"
        echo "  run     启动内核（QEMU）"
        echo "  debug   调试模式（QEMU 暂停等待 GDB）"
        echo "  (无参数) 构建 + 启动"
        exit 1
        ;;
esac
