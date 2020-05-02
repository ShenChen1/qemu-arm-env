#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <linux/netlink.h>
#include <sys/socket.h>
#include <strings.h>
#include <string.h>

/* 自定义协议号 */
#define NETLINK_DEMO 31

/* 自定义消息类型 */
#define NLMSG_ECHO_REQUEST 0x11
#define NLMSG_ECHO_RESPONSE 0x12

/* 最大协议负载 */
#define MAX_PAYLOAD 101

struct sockaddr_nl src_addr, dst_addr;
struct iovec iov;
int sockfd;
struct nlmsghdr *nlh = NULL;
struct msghdr msg;

int main(int argc, char **argv)
{
    if (argc != 2) {
        printf("usage: ./nl_client.out <msg_str>\n");
        exit(-1);
    }

    /* 创建NETLINK_DEMO协议的socket */
    sockfd = socket(AF_NETLINK, SOCK_DGRAM, NETLINK_DEMO);

    /* 设置本地端点 */
    bzero(&src_addr, sizeof(src_addr));
    src_addr.nl_family = AF_NETLINK;
    src_addr.nl_pid = getpid();
    src_addr.nl_groups = 0; //未加入多播组
    bind(sockfd, (struct sockaddr*)&src_addr, sizeof(src_addr));

    /* 设置目的端点 */
    bzero(&dst_addr, sizeof(dst_addr));
    dst_addr.nl_family = AF_NETLINK;
    dst_addr.nl_pid = 0; // 表示内核
    dst_addr.nl_groups = 0; //未指定接收多播组

    /* 构造发送消息 */
    nlh = malloc(NLMSG_SPACE(MAX_PAYLOAD));
    nlh->nlmsg_len = NLMSG_SPACE(MAX_PAYLOAD);
    nlh->nlmsg_pid = getpid();
    nlh->nlmsg_flags = 0;
    nlh->nlmsg_type = NLMSG_ECHO_REQUEST;
    strcpy(NLMSG_DATA(nlh), argv[1]);
    iov.iov_base = (void *)nlh;
    iov.iov_len = nlh->nlmsg_len;
    msg.msg_name = (void *)&dst_addr;
    msg.msg_namelen = sizeof(dst_addr);
    msg.msg_iov = &iov;
    msg.msg_iovlen = 1;

    /* 向内核模块发送消息 */
    sendmsg(sockfd, &msg, 0);

    /* 接收来自内核模块的应答消息并打印 */
    memset(nlh, 0, NLMSG_SPACE(MAX_PAYLOAD));
    recvmsg(sockfd, &msg, 0);
    printf(" Received message: %s\n", NLMSG_DATA(nlh));
}
