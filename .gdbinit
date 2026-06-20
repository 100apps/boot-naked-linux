set confirm off
set print pretty on
set substitute-path /build/linux linux-src
set substitute-path /build .
add-symbol-file init-debug

# 常用断点（取消注释即可使用）：
#
# 在用户态 init 执行前断住，可以看完整的内核调用栈 (bt)：
break kernel_execve
#
# 在 init 发起系统调用时断在内核侧，观察系统调用处理栈：
#   break __arm64_sys_write
#   break __arm64_sys_reboot
#
# === 网络栈调试断点 ===
#
# socket() 系统调用入口：
#   break __sys_socket
#
# TCP 连接（三次握手）：
#   break tcp_v4_connect
#
# 数据发送路径 (应用层 → 网卡)：
#   break tcp_sendmsg
#   break ip_output
#   break __dev_queue_xmit
#
# 数据接收路径 (网卡 → 应用层)：
#   break ip_rcv
#   break tcp_v4_rcv
#   break tcp_v4_do_rcv
