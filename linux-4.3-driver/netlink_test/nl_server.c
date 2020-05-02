#include <linux/module.h>
#include <linux/netlink.h>
#include <net/netlink.h>
#include <net/net_namespace.h>

/* 自定义协议号 */
#define NETLINK_DEMO 31

/* 自定义消息类型 */
#define NLMSG_ECHO_REQUEST 0x11
#define NLMSG_ECHO_RESPONSE 0x12

/* 内核端socket */
static struct sock *sk;

/* 回调函数，接收到来自用户进程的消息时调用 */
static void nl_demo_data_ready(struct sk_buff *skb);

/* 内核模块初始化函数 */
int __init nl_demo_init(void)
{
    struct netlink_kernel_cfg nl_cfg = {
        .input = nl_demo_data_ready,
    };

    sk = netlink_kernel_create(&init_net, NETLINK_DEMO, &nl_cfg);

    if (!sk) {
        printk(KERN_INFO "Failed to init netlink demo module!\n");
        return -1;
    }

    printk(KERN_INFO "Succeed to init netlink demo module!\n");
    return 0;
}

/* 内核模块退出函数 */
void __exit nl_demo_exit(void)
{
    netlink_kernel_release(sk);
    printk(KERN_INFO "Exit netlink demo.\n");
}

static void nl_demo_data_ready(struct sk_buff *skb)
{
    struct nlmsghdr *nlh;
    void *payload;
    struct sk_buff *out_skb;
    void *out_payload;
    struct nlmsghdr *out_nlh;
    int payload_len;

    nlh = nlmsg_hdr(skb);

    switch(nlh->nlmsg_type) {
    case NLMSG_ECHO_REQUEST:
        payload = nlmsg_data(nlh);
        payload_len = nlmsg_len(nlh);

        printk(KERN_INFO "payload_len = %d\n", payload_len);
        printk(KERN_INFO "Recievid: %s, From: %d\n", (char *)payload, nlh->nlmsg_pid);

        out_skb = nlmsg_new(NLMSG_DEFAULT_SIZE, GFP_KERNEL);
        if (!out_skb) goto failure;

        out_nlh = nlmsg_put(out_skb, 0, 0, NLMSG_ECHO_RESPONSE, payload_len+strlen("[from kernel]:"), 0);
        if (!out_nlh) goto failure;

        out_payload = nlmsg_data(out_nlh);
        strcpy(out_payload, "[from kernel]:");
        strcat(out_payload, payload);

        nlmsg_unicast(sk, out_skb, nlh->nlmsg_pid);
        break;
    case NLMSG_ECHO_RESPONSE:
        break;
    default:
        printk(KERN_INFO "Unknow message type recieved!\n");
    }
    return;

failure:
    printk(KERN_INFO "Error in function: nl_demo_data_ready !\n");
}

module_init(nl_demo_init);
module_exit(nl_demo_exit);

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("A simple demo for netlink.");
