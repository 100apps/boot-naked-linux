#!/bin/bash
# 启动 QEMU 调试模式，等端口就绪后输出信号供 VSCode 识别
set -eu

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

pkill -f 'qemu-system-aarch64.*-gdb tcp::1234' 2>/dev/null || true
sleep 0.3

qemu-system-aarch64 \
    -machine virt \
    -cpu cortex-a57 \
    -m 256M \
    -nographic \
    -kernel "$PROJECT_DIR/Image" \
    -initrd "$PROJECT_DIR/initrd" \
    -append "console=ttyAMA0 nokaslr" \
    -no-reboot \
    -netdev user,id=net0 \
    -device virtio-net-pci,netdev=net0 \
    -S -gdb tcp::1234 &

QEMU_PID=$!

for i in $(seq 1 30); do
    if lsof -i :1234 -sTCP:LISTEN >/dev/null 2>&1; then
        echo "QEMU GDB server ready on :1234 (pid=$QEMU_PID)"
        wait $QEMU_PID 2>/dev/null
        exit 0
    fi
    sleep 0.2
done

echo "ERROR: QEMU GDB server failed to start"
kill $QEMU_PID 2>/dev/null
exit 1
