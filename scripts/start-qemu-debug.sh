#!/bin/bash
# 启动 QEMU 调试模式，等端口就绪后输出信号供 VSCode 识别
set -eu

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$PROJECT_DIR/scripts/platform.sh"
detect_platform

pkill -f "$QEMU_BIN.*-gdb tcp::1234" 2>/dev/null || true
sleep 0.3

$QEMU_BIN \
    $QEMU_MACHINE \
    $QEMU_CPU \
    $QEMU_ACCEL \
    -m 256M \
    -nographic \
    -kernel "$PROJECT_DIR/Image" \
    -initrd "$PROJECT_DIR/initrd" \
    -append "console=$QEMU_CONSOLE nokaslr" \
    -no-reboot \
    -netdev user,id=net0 \
    -device virtio-net-pci,netdev=net0 \
    -S -gdb tcp::1234 &

QEMU_PID=$!

for i in $(seq 1 30); do
    if check_port_ready; then
        echo "QEMU GDB server ready on :1234 (pid=$QEMU_PID)"
        wait $QEMU_PID 2>/dev/null
        exit 0
    fi
    sleep 0.2
done

echo "ERROR: QEMU GDB server failed to start"
kill $QEMU_PID 2>/dev/null
exit 1
