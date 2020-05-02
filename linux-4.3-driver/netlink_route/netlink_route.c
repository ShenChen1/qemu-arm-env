#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <netinet/in.h>
#include <linux/if_ether.h>
#include <linux/rtnetlink.h>
#include <linux/fib_rules.h>
#include <linux/netfilter/xt_dscp.h>
#include <linux/netconf.h>
#include <linux/if.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define NLMSG_RECEIVE_BUF_SIZE  16384

int create_netlink_socket(void)
{
    int socket_fd;
    int ret = -1;
    int protocol = NETLINK_ROUTE;
    int sndbuf = 131071;
    int rcvbuf = 1024 * 1024;

    uint32_t nl_groups;

    struct sockaddr_nl sa = {
        .nl_family = AF_NETLINK,
        .nl_groups = RTMGRP_LINK,
    };

    socket_fd = socket(AF_NETLINK, SOCK_RAW, protocol);
    if (socket_fd >= 0) {
        ret = bind(socket_fd, (struct sockaddr *)&sa, sizeof(sa));
        if (ret < 0) {
            close(socket_fd);
            socket_fd = -1;
        }
    } else {
        socket_fd = -1;
    }

    /*Set send buffer size*/
    if (setsockopt(socket_fd, SOL_SOCKET, SO_SNDBUF, &sndbuf, sizeof(sndbuf)) < 0) {
        exit(0);
    }

    /*set receive buffer size*/
    if (setsockopt(socket_fd, SOL_SOCKET, SO_RCVBUF, &rcvbuf, sizeof(rcvbuf)) < 0) {
        exit(0);
    }

    return socket_fd;

}

int main()
{
    char buf[NLMSG_RECEIVE_BUF_SIZE] = {0};
    struct iovec iov = {
        .iov_base = buf,
        .iov_len = sizeof(buf),
    };
    struct sockaddr_nl nl_addr;

    /*Need to check */
    /*nl_addr.nl_family = AF_NETLINK*/

    struct msghdr msg = {
        .msg_name = &nl_addr,
        .msg_namelen = sizeof(nl_addr),
        .msg_iov = &iov,
        .msg_iovlen = 1,
    };

    struct nlmsghdr *nlh = (struct nlmsghdr *)iov.iov_base;

    int ret = 0;
    int fd = create_netlink_socket();

    while (1) {
        ret = recvmsg(fd, &msg, 0);

        if (ret == -1) {
            continue;
        }

        if (ret < (ssize_t)sizeof(*nlh)) {
            return -1;
        }
        if (sizeof(nl_addr) != msg.msg_namelen) {
            return -1;
        }
        if (msg.msg_flags & MSG_TRUNC) {
            exit(0);
        }

        switch (nlh->nlmsg_type) {
        case RTM_NEWLINK:
        case RTM_DELLINK:
        case RTM_SETLINK:
            break;
        }
    }
    return 0;
}
