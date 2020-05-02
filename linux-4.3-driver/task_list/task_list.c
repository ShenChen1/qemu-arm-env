#include <linux/module.h>
#include <linux/sched.h>

static int __init task_list_init(void)
{
    struct task_struct *task;  
    task = &init_task;  
          
    for_each_process(task)  
    {  
        printk("---PID: %d, name: %s, state: %ld---\n", 
                task->pid, task->comm, task->state);  
        show_stack(task, NULL);  
        printk("\n");  
    }  
    
    printk("backtrace of current task:%s\n", current->comm);
    show_stack(NULL, NULL);  

	return 0;
}

static void __exit task_list_exit(void)
{
	printk("Goodbye Kernel!\n");
}

module_init(task_list_init);
module_exit(task_list_exit);

MODULE_LICENSE( "GPL" );

