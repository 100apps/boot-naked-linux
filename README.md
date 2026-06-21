# Boot Naked Linux

从零构建一个最小的 Linux 内核，启动后运行 5 种网络 I/O 模型对比 Demo，然后关机。

适合想理解 Linux 内核启动原理和网络 I/O 模型的开发者。你可以用 VSCode 单步跟踪内核从第一行代码到执行你的 init 程序的全过程。

```
内核 5.6 MB + init 312 KB → 启动并运行 5 种 I/O 模型 Demo
```

> 基于 [Boot a Naked Linux](https://nick.zoic.org/art/boot-naked-linux/)，支持 macOS / Linux / Windows (WSL)，x86_64 和 arm64 架构。
>
> 📊 [网络 I/O 模型调用链路对比图](https://100apps.github.io/boot-naked-linux/network-io-models.html)
> 🧠 [内核本质理解：2700 万行代码在干什么](https://100apps.github.io/boot-naked-linux/kernel-concepts.html)

---

## 快速开始

### 前置条件

| 平台 | 需要安装 |
|------|----------|
| **macOS** | [Docker Desktop](https://www.docker.com/products/docker-desktop/) + [Homebrew](https://brew.sh)（脚本会自动 `brew install qemu`） |
| **Linux** | [Docker Engine](https://docs.docker.com/engine/install/)（脚本会自动 `apt/dnf/pacman install qemu-system`） |
| **Windows** | [WSL 2](https://learn.microsoft.com/windows/wsl/install) + 在 WSL 内按 Linux 步骤操作 |

### 构建 & 启动

```bash
git clone https://github.com/100apps/boot-naked-linux.git
cd boot-naked-linux

# 一键构建 + 启动（首次约 5-10 分钟）
./boot-naked-linux.sh
```

脚本会自动检测你的操作系统和 CPU 架构（arm64/x86_64），选择正确的 QEMU 和内核配置。

看到以下输出就成功了：

```
Run /init as init process
=== Linux 网络 I/O 模型 Demo ===

Network configured: 10.0.2.15/24 gw 10.0.2.2

=== [1/5] Blocking I/O ===
    connect() 返回 0
    Response: HTTP/1.1 200 OK ...

=== [2/5] Non-blocking I/O + busy poll ===
    connect() 返回 -1, errno=115 (Operation now in progress)
    select() 返回 1 (fd 可写=连接完成)
    Response: HTTP/1.1 200 OK ...

=== [3/5] select (I/O Multiplexing) ===
    select() 返回 2 个就绪 fd
    Response: HTTP/1.1 200 OK ...

=== [4/5] epoll (I/O Multiplexing) ===
    epoll_wait() 返回 2 个就绪事件
    Response: HTTP/1.1 200 OK ...

=== [5/5] io_uring (Async I/O) ===
    connect 完成, res=0
    write 完成, res=59 字节
    read 完成, res=423 字节
    Response: HTTP/1.1 200 OK ...

=== All demos completed ===
reboot: Power down
```

**其他命令：**

```bash
./boot-naked-linux.sh build    # 仅构建
./boot-naked-linux.sh run      # 仅启动（需要先构建）
./boot-naked-linux.sh debug    # 调试模式（QEMU 暂停，等待 GDB 连接）
```

---

## 内核调试

### 环境准备

1. VSCode 安装 [Native Debug](https://marketplace.visualstudio.com/items?itemName=webfreak.debug) 扩展（注意：不是 C/C++ 扩展，因为 cppdbg 不支持远程调试 aarch64）
2. 安装 GDB：
   - **macOS arm64:** `brew install aarch64-elf-gdb`
   - **macOS x86_64:** `brew install x86_64-elf-gdb`
   - **Linux:** `sudo apt install gdb`（或 dnf/pacman）
3. 运行过 `./boot-naked-linux.sh build`

### VSCode 一键调试

1. 用 VSCode 打开本项目
2. 按 **F5**，选择 **Debug Linux Kernel**
3. 自动停在 `start_kernel()`，按 **F5 继续**执行到断点
4. 可以在 `init.c` 的 `main()` 上设断点，调试你自己的 init 程序

> GDB 路径通过 `scripts/gdb-wrapper.sh` 自动检测，无需手动配置。

> **调试配置说明**
>
> | 配置名 | 用途 |
> |--------|------|
> | Debug Linux Kernel | F5 一键启动（自动开 QEMU + 连 GDB） |
> | Debug Linux Kernel (Attach) | 先手动 `./boot-naked-linux.sh debug` 再附加 GDB |

### 命令行调试

```bash
# 终端 1
./boot-naked-linux.sh debug

# 终端 2（脚本会输出正确的 GDB 命令）
# arm64 macOS:
aarch64-elf-gdb vmlinux -ex "source .gdbinit" -ex "target remote :1234" -ex "break start_kernel" -ex "continue"

# x86_64 Linux:
gdb vmlinux -ex "source .gdbinit" -ex "target remote :1234" -ex "break start_kernel" -ex "continue"
```

### 踩坑记录

| 问题 | 原因和解决 |
|------|-----------|
| VSCode F5 卡住不动 | QEMU `-S` 模式无输出，VSCode 等不到任务就绪信号。本项目用 `scripts/start-qemu-debug.sh` 轮询端口就绪后输出信号解决 |
| `Specified argument was out of range (arch)` | cppdbg 不支持远程 aarch64 调试。改用 Native Debug 扩展 |
| 调试启动后一闪而退 | `stopAtEntry` 对内核无效。改用 `autorun` 中显式 `break start_kernel` |
| 断点命中但看不到源码 | 需要 `set substitute-path` 映射 Docker 内路径到本地 `linux-src/`。已在 `.gdbinit` 中配置 |
| `init.c` 中打断点提示找不到源文件 | init 需要带 `-g` 编译，GDB 需要 `add-symbol-file init-debug` 加载符号。已在 `.gdbinit` 中配置 |

---

## 1 小时内核研学指南

按以下顺序设断点、单步跟踪，你能在 1 小时内走通内核启动的核心路径。

### 第一站：内核入口 — `start_kernel()`

**文件：** `linux-src/init/main.c:903`

这是 Linux 内核的 `main()` 函数。在汇编完成最底层的 CPU 初始化后，控制权交到这里。它调用约 100 个子系统的初始化函数，顺序严格不可调换。

```
break start_kernel → F5 继续 → 停在 init/main.c:905
```

**关键调用链（按执行顺序）：**

```c
start_kernel()                    // ← 你在这里
├── setup_arch()                  // 解析设备树，初始化内存布局
├── mm_core_init()                // 内存管理核心（伙伴系统、SLAB 分配器）
├── sched_init()                  // 初始化调度器（还没有进程可调度）
├── init_IRQ()                    // 中断控制器初始化
├── timekeeping_init()            // 时钟子系统
├── console_init()                // 控制台初始化（从这里开始你能看到 printk 输出）
├── vfs_caches_init()             // VFS 虚拟文件系统
├── fork_init()                   // 设置 max_threads，初始化 task_struct 缓存
├── signals_init()                // 信号机制
└── rest_init()                   // 创建第一个用户进程 → 见第二站
```

**动手试：** 在 `console_init()` 前后各设一个断点，观察 QEMU 终端——`console_init()` 之前你看不到任何内核日志输出，之后 `printk` 的积压消息会一次性打出来。

### 第二站：创建第一个进程 — `rest_init()`

**文件：** `linux-src/init/main.c:701`

```
break rest_init → F5 继续
```

```c
rest_init()
├── user_mode_thread(kernel_init, ...)  // 创建 PID 1（init 进程）
├── kernel_thread(kthreadd, ...)        // 创建 PID 2（内核线程管理器）
├── complete(&kthreadd_done)            // 通知 kernel_init 可以继续了
└── cpu_startup_entry()                 // 当前线程变成 idle 进程（PID 0）
```

到这里，Linux 的三个原始进程全部诞生：

| PID | 名称 | 角色 |
|-----|------|------|
| 0 | idle/swapper | 无事可做时运行，永不退出 |
| 1 | init | 第一个用户态进程，所有用户进程的祖先 |
| 2 | kthreadd | 内核线程的父进程 |

**动手试：** 在 `user_mode_thread` 这一行单步，然后在 GDB 中执行 `print pid`，你会看到返回值是 `1`。

### 第三站：从内核态到用户态 — `kernel_init()`

**文件：** `linux-src/init/main.c:1460`

```
break kernel_init → F5 继续
```

```c
kernel_init()
├── kernel_init_freeable()
│   ├── do_basic_setup()          // 执行所有 module_init() —— 驱动都在这里初始化
│   ├── wait_for_initramfs()      // 等待 initramfs 解压完成
│   └── console_on_rootfs()       // 打开 /dev/console
├── free_initmem()                // 释放所有 __init 标记的内存
├── system_state = SYSTEM_RUNNING // 系统正式进入运行状态
└── run_init_process(ramdisk_execute_command)  // 执行 /init → 见第四站
```

**动手试：** 在 `free_initmem()` 前后分别观察内存，GDB 中执行：
```
print nr_free_pages()
```
你会看到可用页数增加——`__init` 段被释放回伙伴系统了。

### 第四站：执行你的程序 — `run_init_process()`

**文件：** `linux-src/init/main.c:1378`

```
break run_init_process → F5 继续
```

```c
run_init_process("/init")
└── kernel_execve("/init", argv_init, envp_init)
    // 这是内核态的 execve —— 它会：
    // 1. 打开 /init（你的 ELF 二进制）
    // 2. 解析 ELF 头，映射 .text/.data 段
    // 3. 设置用户态栈
    // 4. 跳转到 ELF 入口点
    // 从此以后，CPU 运行在用户态
```

**动手试：** 单步到 `kernel_execve` 返回后，再在 `init.c` 的 `main` 设断点并继续，你会停在自己的代码里——从内核态穿越到了用户态。

### 第五站：你的 init 程序

**文件：** `init.c`

```
break main → F5 继续
```

init 程序会依次运行 5 种网络 I/O 模型 Demo，每种发一个 HTTP GET 请求到 httpbin.org，然后关机。你可以在 `demo_blocking()`、`demo_epoll()`、`demo_io_uring()` 等函数上设断点，单步看每种模型的执行路径。

**动手试：** 单步到 `connect()` 调用前暂停，在 GDB 中查看 `sockfd` 的值——这就是内核为你创建的 socket 文件描述符。

### 第六站：跟踪一个 HTTP 请求穿越内核网络栈

这是最精彩的部分——你可以用断点跟踪一个 HTTP 请求从用户态 `connect()` 到网卡发出 SYN 包的完整路径。

**在 GDB 控制台中依次设置这些断点：**

```
break tcp_v4_connect
break ip_output
break __dev_queue_xmit
break ip_rcv
break tcp_v4_rcv
continue
```

**发送路径（你的 `connect()` → SYN 包从网卡发出）：**

```
connect()                         ← 用户态系统调用
└── __sys_connect()               ← 内核态入口
    └── tcp_v4_connect()          ← TCP 层：构造 SYN 包
        └── ip_output()           ← IP 层：加 IP 头，查路由表
            └── __dev_queue_xmit() ← 设备层：推入网卡发送队列
                └── virtio-net    ← 驱动层：通过 virtio 发给 QEMU
```

**接收路径（SYN-ACK 从网卡 → 你的 `connect()` 返回）：**

```
virtio-net 中断               ← 网卡收到 SYN-ACK
└── ip_rcv()                   ← IP 层：解析 IP 头，判断协议
    └── tcp_v4_rcv()           ← TCP 层：匹配到 socket，更新状态
        └── tcp_v4_do_rcv()    ← 三次握手完成，connect() 返回 0
```

**动手试：**

1. 断在 `tcp_v4_connect` 后执行 `bt`，你会看到从 `__sys_connect` 到 TCP 层的完整调用栈
2. 断在 `ip_output` 时执行 `print skb->len`，看 SYN 包的大小
3. 断在 `tcp_v4_rcv` 时你正在处理从 httpbin.org 返回的 SYN-ACK
4. 继续执行，下一次 `tcp_v4_rcv` 就是 HTTP 响应数据

### 理解内核的运行时模型

调试时你会发现：断在 `ksys_write` 时，调用栈里没有 `start_kernel`。这不是 bug，而是 Linux 内核的核心设计。

**内核有两个截然不同的阶段：**

| 阶段 | 模型 | 栈的起点 |
|------|------|---------|
| **启动阶段** | 顺序执行，像普通程序 | `start_kernel()` |
| **运行阶段** | 事件驱动，像中断处理器 | 异常向量表入口（`el0t_64_sync` 等） |

**启动阶段**：`start_kernel()` 像 `main()` 一样顺序执行，初始化完所有子系统后，通过 `kernel_execve` 启动 init 进程，自己变成 idle 循环。`start_kernel` 的栈帧到此结束，永远不会再出现。

**运行阶段**：内核不主动运行。CPU 在用户态执行你的 init.c，只有三种事件能触发内核代码：

```
┌─────────────────────────────────────────────────────────────┐
│                        用户态 (EL0)                          │
│                                                             │
│   init.c: write(2, buf, 46)   ← 执行 svc #0 指令            │
│                                                             │
├──────────────── 硬件特权级切换 ──────────────────────────────┤
│                                                             │
│                        内核态 (EL1)                          │
│                                                             │
│   异常向量表（启动阶段 trap_init 注册的）                      │
│     → el0t_64_sync           // 异常入口（汇编）              │
│     → el0_svc_common         // 识别为系统调用                │
│     → invoke_syscall         // 查系统调用号表                │
│     → ksys_write             // 你的断点在这里                │
│       → vfs_write            // VFS 层                      │
│         → 驱动层 write       // 最终写到串口/终端             │
│     → eret 返回用户态        // 回到 init.c 的下一条指令      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

| 入口 | 触发方式 | 例子 |
|------|---------|------|
| **系统调用** | 用户态执行 `svc` 指令 | `write()`, `socket()`, `connect()`, `reboot()` |
| **硬件中断** | 外设发信号给 CPU | 网卡收到数据包、定时器 tick |
| **异常** | CPU 执行出错 | 缺页（page fault）、非法指令 |

每次事件都产生一条**独立的内核调用栈**，从异常向量表入口开始，处理完毕后 `eret` 返回用户态。这就是为什么系统调用断点的调用栈永远从 `el0t_64_sync` 开始，而不是从 `start_kernel` 开始——它们是完全独立的入口点。

**对应到 init.c 的完整生命周期：**

```
start_kernel                          ← break start_kernel 能看到
  → kernel_init
    → kernel_execve("/init")          ← break kernel_execve 能看到
      ──── eret 进入用户态 ────
        main()
          fprintf("Hello")
            → svc → ksys_write        ← break ksys_write 能看到
          mount("/proc")
            → svc → __arm64_sys_mount
          socket()
            → svc → __sys_socket      ← break __sys_socket
          connect()
            → svc → tcp_v4_connect    ← break tcp_v4_connect
          write(sockfd, request)
            → svc → tcp_sendmsg       ← break tcp_sendmsg
          ──── 网卡收到响应包 ────
            → irq → tcp_v4_rcv        ← break tcp_v4_rcv（中断栈）
          read(sockfd, buf)
            → svc → tcp_recvmsg
          reboot()
            → svc → __arm64_sys_reboot
```

每一次 `svc` / `irq` 都是一条独立的内核栈，互不关联。**Linux 内核不是一个持续运行的程序，而是一组事件处理函数。**

**动手试：**

1. 断在 `ksys_write` 后执行 `bt`，观察栈底是 `el0t_64_sync`（系统调用入口），不是 `start_kernel`
2. 断在 `tcp_v4_rcv` 后执行 `bt`，观察栈底是中断入口（`el0_irq` 或 `el1_irq`），同样不是 `start_kernel`
3. 对比 `break kernel_execve` 的调用栈——那里你能看到 `kernel_init → start_kernel` 的完整启动链

### 网络栈关键函数速查

| 层 | 函数 | 文件 | 说明 |
|----|------|------|------|
| **系统调用** | `__sys_socket()` | `net/socket.c:1711` | 创建 socket |
| **TCP 发送** | `tcp_v4_connect()` | `net/ipv4/tcp_ipv4.c:218` | 发起三次握手 |
| | `tcp_sendmsg()` | `net/ipv4/tcp.c:1352` | 应用数据 → TCP 发送缓冲区 |
| **IP 层** | `ip_output()` | `net/ipv4/ip_output.c:427` | 加 IP 头，发出去 |
| | `ip_rcv()` | `net/ipv4/ip_input.c:560` | 收到 IP 包，分发到上层协议 |
| **TCP 接收** | `tcp_v4_rcv()` | `net/ipv4/tcp_ipv4.c:2177` | 收到 TCP 段，匹配 socket |
| **设备层** | `__dev_queue_xmit()` | `net/core/dev.c:4340` | 推入网卡发送队列 |

### 完整启动路径速查

```
CPU 上电 → head.S (汇编) → start_kernel()
           │
           ├─ [硬件初始化] setup_arch → mm_core_init → init_IRQ → timekeeping_init
           ├─ [核心子系统] sched_init → vfs_caches_init → fork_init
           ├─ [控制台就绪] console_init → 从此 printk 可见
           └─ rest_init()
              │
              ├─ PID 1: kernel_init()
              │         ├─ do_basic_setup → 驱动初始化
              │         ├─ wait_for_initramfs → 解压 initrd
              │         ├─ free_initmem → 释放 __init 段
              │         └─ run_init_process("/init")
              │            └─ kernel_execve → 切换到用户态
              │               └─ 你的 init.c main() 开始执行
              │
              ├─ PID 2: kthreadd → 管理所有内核线程
              └─ PID 0: cpu_startup_entry → idle 循环
```

### 内核关键子系统速查

在调试过程中你会遇到这些子系统，每个都值得深入了解：

| 子系统 | 入口函数 | 文件 | 一句话说明 |
|--------|----------|------|-----------|
| **内存管理** | `mm_core_init()` | `mm/mm_init.c` | 建立伙伴系统和 SLAB 分配器，之后 `kmalloc` 才可用 |
| **进程调度** | `sched_init()` | `kernel/sched/core.c` | 初始化运行队列和 CFS 调度器 |
| **中断** | `init_IRQ()` | `arch/arm64/kernel/irq.c` | 配置 GIC 中断控制器 |
| **虚拟文件系统** | `vfs_caches_init()` | `fs/dcache.c` | 初始化 dentry/inode 缓存，挂载 rootfs |
| **设备模型** | `driver_init()` | `drivers/base/init.c` | 建立 `/sys` 的设备树结构 |
| **时钟** | `timekeeping_init()` | `kernel/time/timekeeping.c` | 初始化系统时钟源 |
| **控制台** | `console_init()` | `kernel/printk/printk.c` | 注册控制台设备，积压的日志在此刻输出 |
| **网络栈** | `tcp_v4_connect()` | `net/ipv4/tcp_ipv4.c` | TCP 连接发起，三次握手从这里开始 |
| **IP 协议** | `ip_rcv()` / `ip_output()` | `net/ipv4/ip_input.c` | IP 包的收发入口 |

### 第七站：网络 I/O 模型对比 — 从阻塞到 io_uring

init.c 依次运行 5 种网络 I/O 模型，每种发一个 HTTP GET 请求。你可以通过断点走遍每种模型的完整调用链路。

> 📊 [完整调用链路对比图](https://100apps.github.io/boot-naked-linux/network-io-models.html)

| 模型 | 内核入口 | 等待机制 | 编程模型 |
|------|---------|---------|---------|
| **Blocking** | `__arm64_sys_connect` → `tcp_v4_connect` → `inet_wait_for_connect` | `wait_queue` + `schedule()` | 同步阻塞 |
| **Non-blocking** | `__arm64_sys_connect` → `tcp_v4_connect`（立即返回 EINPROGRESS） | 轮询 / select | 轮询 |
| **select** | `__arm64_sys_select` → `do_select` | 每个 fd 的 wait_queue，O(n) | 同步多路复用 |
| **epoll** | `__arm64_sys_epoll_wait` → `ep_poll` | `ep->wq` + `ep_poll_callback`，O(1) | 同步多路复用 |
| **io_uring** | `__arm64_sys_io_uring_enter` → `io_submit_sqes` | SQ/CQ ring buffer + kernel worker | 真正异步 |

**调试建议：**

```
# 在 GDB 中依次设置这些断点，观察每种模型的内核路径
break tcp_v4_connect     # 所有模型都经过这里
break inet_wait_for_connect  # 只有 Blocking 模型会到这里
break do_select              # select 模型的核心等待
break ep_poll                # epoll 模型的核心等待
break ep_poll_callback       # epoll 的 fd 就绪回调
break io_submit_sqes         # io_uring 提交请求
break io_cqring_wait         # io_uring 等待完成
```

**本质区别：** 所有模型底层都是 `wait_queue` + `schedule()`，区别在于**谁在等、等什么**：
- Blocking：进程 == 等待者，挂在 socket 的 `sk->sk_wq` 上
- select：进程挂在每个 fd 的等待队列上，任何一个就绪就唤醒
- epoll：进程挂在 epoll 实例的 `ep->wq` 上，fd 就绪时回调 `ep_poll_callback` 加入就绪链表
- io_uring：不需要进程睡眠，内核完成 I/O 后直接写共享内存 ring buffer

---

## 实现原理

### 整体架构

```
┌──────────────────────────────────────────────────┐
│  QEMU (自动选择 aarch64 或 x86_64)                │
│                                                   │
│  ┌────────────┐       ┌────────────┐              │
│  │   Image     │       │   initrd   │              │
│  │  (内核)     │       │ (cpio 归档) │              │
│  │  3 MB       │       │  274 KB    │              │
│  └─────┬──────┘       └─────┬──────┘              │
│        │                     │                     │
│   1. 内核启动            2. 解压 initramfs          │
│      初始化硬件             到根文件系统 /            │
│        │                     │                     │
│        └──────────┬──────────┘                     │
│                   ▼                                │
│     3. 执行 /init（第一个用户态进程）                 │
│        → "Hello from init.c!"                      │
│        → reboot(RB_POWER_OFF)                      │
└──────────────────────────────────────────────────┘
```

### 跨平台支持

脚本通过 `scripts/platform.sh` 自动检测运行环境：

| 检测项 | arm64 (Apple Silicon / ARM Linux) | x86_64 (Intel Mac / x86 Linux) |
|--------|-----------------------------------|-------------------------------|
| QEMU | `qemu-system-aarch64 -machine virt -cpu cortex-a57` | `qemu-system-x86_64 -machine pc -cpu qemu64` |
| 硬件加速 | 无 | Linux 自动启用 `-enable-kvm` |
| 内核串口 | PL011 (`ttyAMA0`) | 8250 (`ttyS0`) |
| 内核镜像 | `arch/arm64/boot/Image` | `arch/x86/boot/bzImage` |
| GDB (macOS) | `aarch64-elf-gdb` | `x86_64-elf-gdb` |
| GDB (Linux) | `gdb` | `gdb` |

### Linux 启动的最小要素

一个 Linux 系统启动只需要两样东西：

- **内核 (Image)** — 操作系统本体
- **init 程序** — 内核完成初始化后执行的第一个用户态进程 (PID 1)

标准发行版中 init 是 systemd，会启动几百个服务。但内核并不关心 init 做什么——它只要求 `/init` 是一个可执行文件。我们的 init 只做两件事：打印一句话，然后关机。

### init 程序为什么要静态编译

```c
int main(int argc, char **argv) {
    fprintf(stderr, "Hello from init.c!\n");
    reboot(RB_POWER_OFF);
}
```

`gcc -static` 把 glibc（`fprintf`、`reboot` 的实现）直接打包进二进制。我们的根文件系统里只有这一个文件，没有任何共享库。

> 如果 init 退出而没有调用 `reboot()`，内核会 panic——PID 1 不允许退出。

### initrd 的制作

```bash
echo 'init' | cpio -o --format=newc | gzip -c > initrd
```

1. `echo 'init'` — 列出要打包的文件
2. `cpio --format=newc` — 内核只认这种 cpio 格式
3. `gzip` — 内核启动时用内置解压器解压到 ramfs 作为根目录 `/`

### 内核裁剪

`make tinyconfig` 关闭几乎所有功能，然后 `kernel.config.sh` 按需开启：

| 类别 | 配置项 | 作用 |
|------|--------|------|
| **启动** | `CONFIG_BLK_DEV_INITRD` + `CONFIG_RD_GZIP` | 加载并解压 initrd |
| **执行** | `CONFIG_BINFMT_ELF` | 支持 ELF 格式 |
| **输出** | `CONFIG_TTY` + 串口驱动 | arm64: PL011, x86_64: 8250 |
| **平台** | `CONFIG_VIRTIO` + `CONFIG_PCI` | QEMU 虚拟设备总线 |
| **调试** | `CONFIG_DEBUG_INFO` + `CONFIG_FRAME_POINTER` | 调试符号 + 栈帧 |

### 为什么用 Docker

macOS 没有 Linux 工具链。Docker Desktop 在 Apple Silicon 上跑 arm64 Linux VM，gcc 直接产出对应架构的二进制，不需要交叉编译。Linux 用户同样受益于一致的构建环境。

### QEMU 启动参数

脚本根据架构自动选择参数。以 arm64 为例：

```bash
qemu-system-aarch64 \
    -machine virt         # QEMU 虚拟平台
    -cpu cortex-a57       # ARMv8-A 处理器
    -m 256M               # 256MB 内存
    -nographic            # 输出到终端
    -kernel Image         # 直接加载内核（跳过 bootloader）
    -initrd initrd        # 加载初始内存盘
    -append "console=ttyAMA0"   # 控制台绑定到串口
    -no-reboot            # reboot() 后退出 QEMU
```

x86_64 系统上会自动切换为 `qemu-system-x86_64 -machine pc -cpu qemu64 -append "console=ttyS0"`，Linux 有 KVM 时自动启用硬件加速。

### 内核代码量

Linux 内核有 **2700 万行代码**，但你的项目裁剪后只用了约 **350 万行**（tinyconfig 排除掉了 GPU、USB、WiFi、蓝牙、音频等不需要的驱动）。真正参与 Demo 的代码可能不到 10 万行。

> 🧠 详细分析：[内核本质理解 — 2700 万行代码在干什么](https://100apps.github.io/boot-naked-linux/kernel-concepts.html)

### 启动时间线

```
  0 ms    QEMU 加载 Image + initrd 到内存
  0 ms    内核开始执行，初始化 CPU、内存
 50 ms    初始化串口驱动、挂载 devtmpfs
 80 ms    解压 initrd → / 下出现 /init
100 ms    "Run /init as init process"
100 ms    "Hello from init.c!"
110 ms    "reboot: Power down" → QEMU 退出
```

---

## 项目结构

```
boot-naked-linux/
├── boot-naked-linux.sh     一键脚本（构建/启动/调试，自动检测平台）
├── init.c                  init 程序源码（5 种网络 I/O 模型 Demo）
├── kernel.config.sh        内核配置脚本（按架构启用不同驱动）
├── Dockerfile              Docker 构建文件（支持 arm64/amd64）
├── .gdbinit                GDB 初始化（路径映射 + init 符号加载 + 所有模型断点）
├── network-io-models.html  网络 I/O 模型调用链路对比图
├── kernel-concepts.html    内核本质理解（事件处理器 + 数据结构 | 裁判 + 管家 + 翻译官）
├── scripts/
│   ├── platform.sh         平台检测（OS/架构/QEMU/GDB 自动配置）
│   ├── gdb-wrapper.sh      GDB 包装器（VSCode 用，自动选择正确的 GDB）
│   └── start-qemu-debug.sh QEMU 调试启动器（供 VSCode 使用）
├── .vscode/
│   ├── launch.json         调试配置（F5 一键调试）
│   ├── tasks.json          QEMU 启动/停止/重建任务
│   └── settings.json       内核源码索引配置
│
│  以下为构建产物（已在 .gitignore 中排除）：
├── Image                   内核镜像（arm64: Image, x86_64: bzImage）
├── vmlinux                 带调试符号的内核 ELF
├── init-debug              带调试符号的 init
├── initrd                  初始内存盘
└── linux-src/              内核源码（调试源码跳转用）
```

---

## 常见问题

**Q: 首次构建很慢？**
Docker 需要下载 Ubuntu 镜像 + 内核源码 + 编译，首次约 5-10 分钟。后续利用 Docker 缓存，几秒完成。

**Q: 启动报 "no cpio magic"？**
initrd 格式不对。确保用 `cpio --format=newc` 生成，且内核开启了 `CONFIG_RD_GZIP`。

**Q: VSCode 调试看不到源码？**
确保运行过 `./boot-naked-linux.sh build`，它会提取 `linux-src/` 目录。

**Q: 想修改 init 程序？**
编辑 `init.c` 后重新 `./boot-naked-linux.sh build`。

**Q: Windows 上怎么用？**
安装 [WSL 2](https://learn.microsoft.com/windows/wsl/install)，在 WSL 终端内按 Linux 步骤操作即可。VSCode 使用 [Remote - WSL](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-wsl) 扩展打开项目。

**Q: 我是 x86_64 机器，能用吗？**
可以。脚本自动检测架构，会使用 `qemu-system-x86_64` 和对应的内核配置。Linux 有 KVM 时还会自动启用硬件加速。

---

## License

MIT
