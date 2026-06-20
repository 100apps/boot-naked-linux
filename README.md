# Boot Naked Linux

从零构建一个最小的 Linux 内核，启动后输出 `Hello from init.c!` 然后关机。

适合想理解 Linux 内核启动原理的开发者。你可以用 VSCode 单步跟踪内核从第一行代码到执行你的 init 程序的全过程。

```
内核 3 MB + init 274 KB → 100ms 内完成启动
```

> 基于 [Boot a Naked Linux](https://nick.zoic.org/art/boot-naked-linux/)，适配 Apple Silicon Mac + VSCode 调试。

---

## 快速开始

**前置条件：** [Docker Desktop](https://www.docker.com/products/docker-desktop/)（已启动）+ [Homebrew](https://brew.sh)

```bash
git clone https://github.com/100apps/boot-naked-linux.git
cd boot-naked-linux

# 一键构建 + 启动（首次约 5-10 分钟）
./boot-naked-linux.sh
```

看到以下输出就成功了：

```
Run /init as init process
Hello from init.c!
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
2. 运行过 `./boot-naked-linux.sh build`

### VSCode 一键调试

1. 用 VSCode 打开本项目
2. 按 **F5**，选择 **Debug Linux Kernel**
3. 自动停在 `start_kernel()`，按 **F5 继续**执行到断点
4. 可以在 `init.c` 的 `main()` 上设断点，调试你自己的 init 程序

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

# 终端 2
aarch64-elf-gdb vmlinux \
    -ex "source .gdbinit" \
    -ex "target remote :1234" \
    -ex "break start_kernel" \
    -ex "continue"
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

**文件：** `init.c:5`

```
break main → F5 继续
```

```c
int main(int argc, char **argv) {
    fprintf(stderr, "Hello from init.c!\n");  // ← 你在这里
    reboot(RB_POWER_OFF);                     // 系统调用 → 内核执行关机
}
```

**动手试：** 单步到 `reboot()` 前暂停，在 GDB 中查看：
```
print argc          → 2
print argv[0]       → "/init"
```
这就是内核传给你的 init 进程的参数。

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

---

## 实现原理

### 整体架构

```
┌──────────────────────────────────────────────────┐
│  QEMU (qemu-system-aarch64 -machine virt)        │
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
| **输出** | `CONFIG_TTY` + `CONFIG_SERIAL_AMBA_PL011` | 串口控制台 |
| **平台** | `CONFIG_VIRTIO` + `CONFIG_PCI` + `CONFIG_OF` | QEMU virt 平台 |
| **调试** | `CONFIG_DEBUG_INFO` + `CONFIG_FRAME_POINTER` | 调试符号 + 栈帧 |

### 为什么用 Docker

macOS 没有 Linux 工具链。Docker Desktop 在 Apple Silicon 上跑 arm64 Linux VM，gcc 直接产出 arm64 二进制，不需要交叉编译。

### QEMU 启动参数

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
├── boot-naked-linux.sh     一键脚本（构建/启动/调试）
├── init.c                  init 程序源码
├── kernel.config.sh        内核配置脚本
├── Dockerfile              Docker 构建文件
├── .gdbinit                GDB 初始化（路径映射 + init 符号加载）
├── scripts/
│   └── start-qemu-debug.sh QEMU 调试启动器（供 VSCode 使用）
├── .vscode/
│   ├── launch.json         调试配置（F5 一键调试）
│   ├── tasks.json          QEMU 启动/停止/重建任务
│   └── settings.json       内核源码索引配置
│
│  以下为构建产物（已在 .gitignore 中排除）：
├── Image                   arm64 Linux 内核（~3 MB）
├── vmlinux                 带调试符号的内核 ELF（~36 MB）
├── init-debug              带调试符号的 init（~627 KB）
├── initrd                  初始内存盘（~274 KB）
└── linux-src/              内核源码（~1.6 GB，调试源码跳转用）
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

**Q: 想换内核版本？**
`KERNEL_VERSION=6.11 ./boot-naked-linux.sh build`

---

## License

MIT
