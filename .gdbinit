set confirm off
set print pretty on
set substitute-path /build/linux linux-src
set substitute-path /build .
add-symbol-file init-debug

# ================================================================
# 网络 I/O 模型调试断点
# ================================================================
# 注意：-O2 编译下 GDB 显示的行号可能与源码行号不一致，
# 这是内联展开导致的正常现象，断点本身是正确的。

# === 用户态 init 入口 ===
# 在 init 执行前断住，可以看完整的内核启动调用栈
break kernel_execve

# === 系统调用入口 ===
# 观察每种模型如何进入内核
break __arm64_sys_socket
break __arm64_sys_connect
break __arm64_sys_write
break __arm64_sys_read
break __arm64_sys_select
break __arm64_sys_epoll_create1
break __arm64_sys_epoll_ctl
break __arm64_sys_epoll_wait
break __arm64_sys_io_uring_setup
break __arm64_sys_io_uring_enter

# === TCP 协议栈内核路径 ===
# 连接建立（三次握手）
break tcp_v4_connect
# 数据发送
break tcp_sendmsg
# 数据接收
break tcp_v4_rcv
# IP 层收包
break ip_rcv

# === 等待/唤醒机制 ===
# 阻塞式 connect 在此睡眠
break inet_wait_for_connect
# socket 状态变化时唤醒
break sock_def_wakeup

# === select/epoll 内核路径 ===
# select 的核心等待
break do_select
# epoll_wait 的核心等待
break ep_poll
# fd 就绪时的回调
break ep_poll_callback

# === io_uring 内核路径 ===
# io_uring 提交
break io_submit_sqes
# io_uring 等待完成
break io_cqring_wait