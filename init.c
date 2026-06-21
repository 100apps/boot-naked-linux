/*
 * init.c — Linux 网络 I/O 模型对比 Demo
 *
 * 运行 5 种模型，每种发一个 HTTP GET 请求到 httpbin.org/get
 * 演示从内核事件驱动到应用层不同 API 风格的差异
 *
 * 模型列表:
 *   1. Blocking I/O (阻塞)
 *   2. Non-blocking I/O + busy poll (非阻塞)
 *   3. select (I/O 多路复用)
 *   4. epoll (I/O 多路复用)
 *   5. io_uring (真正异步 I/O)
 *
 * 编译: gcc -g -static init.c -o init -luring
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <sys/select.h>
#include <sys/epoll.h>
#include <sys/ioctl.h>
#include <sys/time.h>
#include <net/if.h>
#include <net/route.h>
#include <linux/if_packet.h>
#include <liburing.h>

#define TARGET_IP   "52.202.201.157"
#define TARGET_PORT 80
#define HTTP_REQUEST \
    "GET /get HTTP/1.1\r\n" \
    "Host: httpbin.org\r\n" \
    "Connection: close\r\n" \
    "\r\n"

/* ================================================================
 * 网络设置
 * ================================================================ */
static void setup_network(void) {
    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) { perror("socket"); return; }

    struct ifreq ifr;

    /* lo */
    memset(&ifr, 0, sizeof(ifr));
    strncpy(ifr.ifr_name, "lo", IFNAMSIZ);
    ifr.ifr_flags = IFF_UP | IFF_LOOPBACK | IFF_RUNNING;
    ioctl(fd, SIOCSIFFLAGS, &ifr);

    /* 等待 eth0 */
    int retries = 0;
    while (retries < 20) {
        memset(&ifr, 0, sizeof(ifr));
        strncpy(ifr.ifr_name, "eth0", IFNAMSIZ);
        if (ioctl(fd, SIOCGIFFLAGS, &ifr) == 0) break;
        usleep(100000);
        retries++;
    }
    if (retries == 20) { fprintf(stderr, "eth0 not found\n"); close(fd); return; }

    /* 配置 IP */
    memset(&ifr, 0, sizeof(ifr));
    strncpy(ifr.ifr_name, "eth0", IFNAMSIZ);
    struct sockaddr_in *addr = (struct sockaddr_in *)&ifr.ifr_addr;
    addr->sin_family = AF_INET;
    inet_pton(AF_INET, "10.0.2.15", &addr->sin_addr);
    ioctl(fd, SIOCSIFADDR, &ifr);

    addr = (struct sockaddr_in *)&ifr.ifr_netmask;
    addr->sin_family = AF_INET;
    inet_pton(AF_INET, "255.255.255.0", &addr->sin_addr);
    ioctl(fd, SIOCSIFNETMASK, &ifr);

    ifr.ifr_flags = IFF_UP | IFF_RUNNING;
    ioctl(fd, SIOCSIFFLAGS, &ifr);

    /* 默认网关 */
    struct rtentry route;
    memset(&route, 0, sizeof(route));
    addr = (struct sockaddr_in *)&route.rt_dst;
    addr->sin_family = AF_INET; addr->sin_addr.s_addr = 0;
    addr = (struct sockaddr_in *)&route.rt_gateway;
    addr->sin_family = AF_INET;
    inet_pton(AF_INET, "10.0.2.2", &addr->sin_addr);
    addr = (struct sockaddr_in *)&route.rt_genmask;
    addr->sin_family = AF_INET; addr->sin_addr.s_addr = 0;
    route.rt_flags = RTF_UP | RTF_GATEWAY;
    ioctl(fd, SIOCADDRT, &route);

    close(fd);
    fprintf(stderr, "Network configured: 10.0.2.15/24 gw 10.0.2.2\n\n");
}

/* ================================================================
 * 打印响应
 * ================================================================ */
static void print_response(int fd) {
    char buf[512];
    int n = read(fd, buf, sizeof(buf) - 1);
    if (n > 0) {
        buf[n] = '\0';
        fprintf(stderr, "    Response: %.*s...\n", 60, buf);
    }
}

/* ================================================================
 * 模型 1: Blocking I/O — connect/read/write 都是阻塞的
 * 内核: wait_queue + schedule()，进程挂起等待
 * ================================================================ */
static void demo_blocking(void) {
    fprintf(stderr, "=== [1/5] Blocking I/O ===\n");
    fprintf(stderr, "    connect() → 进程睡眠 → 三次握手完成 → 被唤醒\n");

    int fd = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in srv = { .sin_family = AF_INET, .sin_port = htons(TARGET_PORT) };
    inet_pton(AF_INET, TARGET_IP, &srv.sin_addr);

    int ret = connect(fd, (struct sockaddr *)&srv, sizeof(srv));
    fprintf(stderr, "    connect() 返回 %d\n", ret);

    write(fd, HTTP_REQUEST, strlen(HTTP_REQUEST));
    print_response(fd);
    close(fd);
    fprintf(stderr, "\n");
}

/* ================================================================
 * 模型 2: Non-blocking I/O — connect 立即返回 EINPROGRESS
 * 内核: 不调用 wait_woken()，直接返回
 * 应用层: 轮询检查是否就绪（busy poll）
 * ================================================================ */
static void demo_nonblocking(void) {
    fprintf(stderr, "=== [2/5] Non-blocking I/O + busy poll ===\n");
    fprintf(stderr, "    connect() → 立即返回 EINPROGRESS → 轮询等待\n");

    int fd = socket(AF_INET, SOCK_STREAM, 0);
    fcntl(fd, F_SETFL, O_NONBLOCK);

    struct sockaddr_in srv = { .sin_family = AF_INET, .sin_port = htons(TARGET_PORT) };
    inet_pton(AF_INET, TARGET_IP, &srv.sin_addr);

    int ret = connect(fd, (struct sockaddr *)&srv, sizeof(srv));
    fprintf(stderr, "    connect() 返回 %d, errno=%d (%s)\n", ret, errno, strerror(errno));

    /* 用 select 等待 connect 完成（比纯 busy poll 优雅一点） */
    fd_set wfds;
    FD_ZERO(&wfds);
    FD_SET(fd, &wfds);
    struct timeval tv = { .tv_sec = 5 };
    int sel_ret = select(fd + 1, NULL, &wfds, NULL, &tv);
    fprintf(stderr, "    select() 返回 %d (fd 可写=连接完成)\n", sel_ret);

    if (sel_ret > 0) {
        write(fd, HTTP_REQUEST, strlen(HTTP_REQUEST));

        /* 用 select 等待可读 */
        fd_set rfds;
        FD_ZERO(&rfds);
        FD_SET(fd, &rfds);
        tv = (struct timeval){ .tv_sec = 5 };
        select(fd + 1, &rfds, NULL, NULL, &tv);
        print_response(fd);
    }

    close(fd);
    fprintf(stderr, "\n");
}

/* ================================================================
 * 模型 3: select — 同时监听多个 fd
 * 内核: 每次传入整个 fd_set，O(n) 遍历
 * ================================================================ */
static void demo_select(void) {
    fprintf(stderr, "=== [3/5] select (I/O Multiplexing) ===\n");
    fprintf(stderr, "    一次 select() 等待多个 fd 就绪，O(n) 遍历\n");

    /* 创建两个 socket，演示 select 同时监听多个 fd */
    int fd1 = socket(AF_INET, SOCK_STREAM, 0);
    int fd2 = socket(AF_INET, SOCK_STREAM, 0);
    fcntl(fd1, F_SETFL, O_NONBLOCK);
    fcntl(fd2, F_SETFL, O_NONBLOCK);

    struct sockaddr_in srv = { .sin_family = AF_INET, .sin_port = htons(TARGET_PORT) };
    inet_pton(AF_INET, TARGET_IP, &srv.sin_addr);

    connect(fd1, (struct sockaddr *)&srv, sizeof(srv));
    connect(fd2, (struct sockaddr *)&srv, sizeof(srv));

    /* 等待两个连接都完成 */
    int maxfd = (fd1 > fd2 ? fd1 : fd2) + 1;
    int done_fd1 = 0, done_fd2 = 0;
    int loops = 0;
    fd_set wfds, rfds;
    while ((!done_fd1 || !done_fd2) && loops < 20) {
        FD_ZERO(&wfds);
        FD_ZERO(&rfds);
        if (!done_fd1) { FD_SET(fd1, &wfds); FD_SET(fd1, &rfds); }
        if (!done_fd2) { FD_SET(fd2, &wfds); FD_SET(fd2, &rfds); }

        struct timeval tv = { .tv_sec = 5 };
        int ret = select(maxfd, &rfds, &wfds, NULL, &tv);
        fprintf(stderr, "    select() 返回 %d 个就绪 fd\n", ret);

        if (FD_ISSET(fd1, &wfds) && !done_fd1) {
            write(fd1, HTTP_REQUEST, strlen(HTTP_REQUEST)); done_fd1 = 1;
        }
        if (FD_ISSET(fd2, &wfds) && !done_fd2) {
            write(fd2, HTTP_REQUEST, strlen(HTTP_REQUEST)); done_fd2 = 1;
        }
        loops++;
    }

    /* 等待可读 */
    FD_ZERO(&rfds);
    FD_SET(fd1, &rfds); FD_SET(fd2, &rfds);
    struct timeval tv = { .tv_sec = 5 };
    select(maxfd, &rfds, NULL, NULL, &tv);
    if (FD_ISSET(fd1, &rfds)) print_response(fd1);
    if (FD_ISSET(fd2, &rfds)) print_response(fd2);

    close(fd1); close(fd2);
    fprintf(stderr, "\n");
}

/* ================================================================
 * 模型 4: epoll — 内核维护 fd 集合，O(1) 就绪通知
 * 内核: epoll_create 创建 eventpoll 对象（红黑树 + 就绪链表）
 *       epoll_ctl 注册 fd，fd 就绪时回调 ep_poll_callback
 *       epoll_wait 只返回就绪的 fd
 * ================================================================ */
static void demo_epoll(void) {
    fprintf(stderr, "=== [4/5] epoll (I/O Multiplexing) ===\n");
    fprintf(stderr, "    epoll_create → epoll_ctl 注册 → epoll_wait 只返回就绪 fd\n");

    int epfd = epoll_create1(0);
    if (epfd < 0) {
        fprintf(stderr, "    epoll_create1 failed: %s\n", strerror(errno));
        return;
    }

    int fd1 = socket(AF_INET, SOCK_STREAM, 0);
    int fd2 = socket(AF_INET, SOCK_STREAM, 0);
    fcntl(fd1, F_SETFL, O_NONBLOCK);
    fcntl(fd2, F_SETFL, O_NONBLOCK);

    struct sockaddr_in srv = { .sin_family = AF_INET, .sin_port = htons(TARGET_PORT) };
    inet_pton(AF_INET, TARGET_IP, &srv.sin_addr);

    connect(fd1, (struct sockaddr *)&srv, sizeof(srv));
    connect(fd2, (struct sockaddr *)&srv, sizeof(srv));

    /* 注册 EPOLLOUT (等待连接完成) */
    struct epoll_event ev = { .events = EPOLLOUT };
    ev.data.fd = fd1; epoll_ctl(epfd, EPOLL_CTL_ADD, fd1, &ev);
    ev.data.fd = fd2; epoll_ctl(epfd, EPOLL_CTL_ADD, fd2, &ev);

    struct epoll_event events[4];
    int done = 0;
    int loops = 0;
    while (done < 2 && loops < 20) {
        int n = epoll_wait(epfd, events, 4, 5000);
        fprintf(stderr, "    epoll_wait() 返回 %d 个就绪事件\n", n);
        if (n <= 0) { loops++; continue; }
        for (int i = 0; i < n; i++) {
            if (events[i].events & EPOLLOUT) {
                write(events[i].data.fd, HTTP_REQUEST, strlen(HTTP_REQUEST));
                /* 切换为等待 EPOLLIN */
                ev.events = EPOLLIN;
                ev.data.fd = events[i].data.fd;
                epoll_ctl(epfd, EPOLL_CTL_MOD, events[i].data.fd, &ev);
                done++;
            }
        }
    }

    /* 等待可读 */
    if (done >= 2) {
        int n = epoll_wait(epfd, events, 4, 5000);
        for (int i = 0; i < n; i++) {
            if (events[i].events & EPOLLIN)
                print_response(events[i].data.fd);
        }
    }

    close(fd1); close(fd2); close(epfd);
    fprintf(stderr, "\n");
}

/* ================================================================
 * 模型 5: io_uring — 真正异步 I/O，共享内存 ring buffer
 * 内核: SQ ring 提交请求，CQ ring 获取完成事件
 *       无需系统调用即可提交和收割
 * ================================================================ */
static void demo_io_uring(void) {
    fprintf(stderr, "=== [5/5] io_uring (Async I/O) ===\n");
    fprintf(stderr, "    io_uring: SQ ring 提交 → 内核异步执行 → CQ ring 取结果\n");

    struct io_uring ring;
    io_uring_queue_init(8, &ring, 0);

    /* 创建 socket */
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    fcntl(fd, F_SETFL, O_NONBLOCK);

    struct sockaddr_in srv = { .sin_family = AF_INET, .sin_port = htons(TARGET_PORT) };
    inet_pton(AF_INET, TARGET_IP, &srv.sin_addr);

    /* 使用 io_uring 的 connect */
    struct io_uring_sqe *sqe = io_uring_get_sqe(&ring);
    io_uring_prep_connect(sqe, fd, (struct sockaddr *)&srv, sizeof(srv));
    io_uring_sqe_set_data(sqe, (void *)(long)fd);
    io_uring_submit(&ring);
    fprintf(stderr, "    io_uring_submit() 提交 connect 请求\n");

    /* 等待 connect 完成 */
    struct io_uring_cqe *cqe;
    io_uring_wait_cqe(&ring, &cqe);
    fprintf(stderr, "    connect 完成, res=%d\n", cqe->res);
    io_uring_cqe_seen(&ring, cqe);

    /* 提交 write */
    sqe = io_uring_get_sqe(&ring);
    io_uring_prep_write(sqe, fd, HTTP_REQUEST, strlen(HTTP_REQUEST), 0);
    io_uring_submit(&ring);
    io_uring_wait_cqe(&ring, &cqe);
    fprintf(stderr, "    write 完成, res=%d 字节\n", cqe->res);
    io_uring_cqe_seen(&ring, cqe);

    /* 提交 read */
    char buf[512];
    sqe = io_uring_get_sqe(&ring);
    io_uring_prep_read(sqe, fd, buf, sizeof(buf) - 1, 0);
    io_uring_submit(&ring);
    io_uring_wait_cqe(&ring, &cqe);
    if (cqe->res > 0) {
        buf[cqe->res] = '\0';
        fprintf(stderr, "    read 完成, res=%d 字节\n", cqe->res);
        fprintf(stderr, "    Response: %.60s...\n", buf);
    }
    io_uring_cqe_seen(&ring, cqe);

    io_uring_queue_exit(&ring);
    close(fd);
    fprintf(stderr, "\n");
}

/* ================================================================
 * main
 * ================================================================ */
int main(int argc, char **argv) {
    fprintf(stderr, "=== Linux 网络 I/O 模型 Demo ===\n\n");

    mount("devtmpfs", "/dev", "devtmpfs", 0, NULL);
    mount("proc", "/proc", "proc", 0, NULL);
    mount("sysfs", "/sys", "sysfs", 0, NULL);

    setup_network();

    demo_blocking();
    demo_nonblocking();
    demo_select();
    demo_epoll();
    demo_io_uring();

    fprintf(stderr, "=== All demos completed ===\n");
    reboot(RB_POWER_OFF);
}