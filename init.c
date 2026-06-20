#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <net/if.h>
#include <sys/ioctl.h>
#include <net/route.h>

static void setup_network(void) {
    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) {
        perror("socket");
        return;
    }

    /* 启用 lo */
    struct ifreq ifr;
    memset(&ifr, 0, sizeof(ifr));
    strncpy(ifr.ifr_name, "lo", IFNAMSIZ);
    ifr.ifr_flags = IFF_UP | IFF_LOOPBACK | IFF_RUNNING;
    ioctl(fd, SIOCSIFFLAGS, &ifr);

    /* 等待 eth0 出现 */
    int retries = 0;
    while (retries < 20) {
        memset(&ifr, 0, sizeof(ifr));
        strncpy(ifr.ifr_name, "eth0", IFNAMSIZ);
        if (ioctl(fd, SIOCGIFFLAGS, &ifr) == 0)
            break;
        usleep(100000);
        retries++;
    }
    if (retries == 20) {
        fprintf(stderr, "eth0 not found\n");
        close(fd);
        return;
    }
    fprintf(stderr, "eth0 found after %d ms\n", retries * 100);

    /* 配置 eth0 IP */
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
    addr->sin_family = AF_INET;
    addr->sin_addr.s_addr = 0;
    addr = (struct sockaddr_in *)&route.rt_gateway;
    addr->sin_family = AF_INET;
    inet_pton(AF_INET, "10.0.2.2", &addr->sin_addr);
    addr = (struct sockaddr_in *)&route.rt_genmask;
    addr->sin_family = AF_INET;
    addr->sin_addr.s_addr = 0;
    route.rt_flags = RTF_UP | RTF_GATEWAY;
    ioctl(fd, SIOCADDRT, &route);

    close(fd);
    fprintf(stderr, "Network configured: 10.0.2.15/24 gw 10.0.2.2\n");
}

static void do_http_request(void) {
    const char *ip = "52.202.201.157";
    const int port = 80;

    const char *request =
        "GET /get HTTP/1.1\r\n"
        "Host: httpbin.org\r\n"
        "Connection: close\r\n"
        "\r\n";

    fprintf(stderr, "\n=== Connecting to %s:%d ===\n", ip, port);

    int sockfd = socket(AF_INET, SOCK_STREAM, 0);
    if (sockfd < 0) {
        perror("socket");
        return;
    }

    struct sockaddr_in server;
    memset(&server, 0, sizeof(server));
    server.sin_family = AF_INET;
    server.sin_port = htons(port);
    inet_pton(AF_INET, ip, &server.sin_addr);

    fprintf(stderr, "=== TCP connect (SYN → SYN-ACK → ACK) ===\n");
    if (connect(sockfd, (struct sockaddr *)&server, sizeof(server)) < 0) {
        perror("connect");
        close(sockfd);
        return;
    }
    fprintf(stderr, "=== Connected! Sending HTTP GET ===\n");

    write(sockfd, request, strlen(request));

    fprintf(stderr, "=== Response ===\n");
    char buf[1024];
    int n;
    while ((n = read(sockfd, buf, sizeof(buf) - 1)) > 0) {
        buf[n] = '\0';
        fprintf(stderr, "%s", buf);
    }
    fprintf(stderr, "\n=== Done ===\n");

    close(sockfd);
}

int main(int argc, char **argv) {
    fprintf(stderr, "Hello from init.c!\n");

    mount("devtmpfs", "/dev", "devtmpfs", 0, NULL);
    mount("proc", "/proc", "proc", 0, NULL);
    mount("sysfs", "/sys", "sysfs", 0, NULL);

    setup_network();
    do_http_request();

    reboot(RB_POWER_OFF);
}
