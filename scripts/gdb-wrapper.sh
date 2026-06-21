#!/bin/bash
# GDB 包装器 — 自动检测并调用正确的 GDB
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/platform.sh"
detect_platform
exec "$GDB_BIN" "$@"
