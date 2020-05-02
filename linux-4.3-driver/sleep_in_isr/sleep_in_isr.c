#include <linux/module.h>
#include <linux/sched.h>
#include <linux/timer.h>
#include <linux/delay.h>

static struct timer_list sii_timer;


static void sii_timer_handler(unsigned long data)
{
    struct task_struct *task = current;
    
    pr_info("--in timer handler--\n");
    pr_info("shoot %16s [%x] task:\n", task->comm, preempt_count());
    //schedule();
    msleep(1000);
    pr_info("--haha~ again once more!!!\n");
    mod_timer(&sii_timer, jiffies + 5 * HZ);
}


static int __init sleep_in_isr_init(void)
{
    init_timer(&sii_timer);
    sii_timer.function = sii_timer_handler;
    sii_timer.expires = jiffies + HZ;
    add_timer(&sii_timer);

    pr_info("init on cpu:%d\n", smp_processor_id());

	return 0;
}

static void __exit sleep_in_isr_exit(void)
{
    del_timer_sync(&sii_timer);
	printk("Goodbye Kernel!\n");
}

module_init(sleep_in_isr_init);
module_exit(sleep_in_isr_exit);

MODULE_LICENSE( "GPL" );

