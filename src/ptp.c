#include "ptp.h"
#include "dryos.h"
#include "menu.h"
#include "tasks.h"

int recv_ptp_data(struct ptp_context *data, char *buf, int size)
	// repeated calls per transaction are ok
{
	while ( size >= BUF_SIZE )
	{
		data->recv_data(data->handle,buf,BUF_SIZE,0,0);
		// XXX check for success??

		size -= BUF_SIZE;
		buf += BUF_SIZE;
	}
	if ( size != 0 )
	{
		data->recv_data(data->handle,buf,size,0,0);
		// XXX check for success??
	}

	return 1;
}

int send_ptp_data(struct ptp_context *data, const char *buf, int size)
	// repeated calls per transaction are *not* ok
{
	int tmpsize;

	tmpsize = size;
	while ( size >= BUF_SIZE )
	{
		if ( data->send_data(data->handle,(void *)buf,BUF_SIZE,tmpsize,0,0,0) )
		{
			return 0;
		}

		tmpsize = 0;
		size -= BUF_SIZE;
		buf += BUF_SIZE;
	}
	if ( size != 0 )
	{
		if ( data->send_data(data->handle,(void *)buf,size,tmpsize,0,0,0) )
		{
			return 0;
		}
	}

	return 1;
}

uint32_t ptp_register_all_handlers()
{
	uint32_t ret = 0x0;

	extern struct ptp_handler _ptp_handlers_start[];
	extern struct ptp_handler _ptp_handlers_end[];

	struct ptp_handler * handler = _ptp_handlers_start;

	for( ; handler < _ptp_handlers_end ; handler++ )
	{
#if defined(POSITION_INDEPENDENT)
        handler->handler = PIC_RESOLVE(handler->handler);
        handler->priv = PIC_RESOLVE(handler->priv);
#endif
		//DebugMsg("[ML] PTP_INIT reg: id=0x%08X h=0x%08X p=0x%08X", handler->id, handler->handler, handler->priv);
		ret |= ptp_register_handler(
				handler->id,
				handler->handler,
				handler->priv
				);
	}

	return ret;
}

static uint32_t ptp_register_ret = 0;
static uint32_t ptp_register_runs = 0;
static uint32_t ptp_register_attempts = 0;
static uint32_t ptp_register_root_last = 0;
static uint32_t ptp_register_last_id = 0;
static uint32_t ptp_register_last_node = 0;

#ifdef CONFIG_750D
#define PTP_750D_OP_LIST_ROOT_PTR 0x00028804

struct ptp_750d_op_node
{
    struct ptp_750d_op_node *next;
    struct ptp_750d_op_node *prev;
    uint16_t id;
    uint16_t unk_0x0a;
    void *handler;
};

struct ptp_750d_op_root
{
    void *lock;
    struct ptp_750d_op_node head;
};

static struct ptp_750d_op_root *ptp_750d_get_op_root(void)
{
    return (struct ptp_750d_op_root *)(*(volatile uint32_t *)PTP_750D_OP_LIST_ROOT_PTR);
}

static uint32_t ptp_750d_get_op_list_root(void)
{
    return (uint32_t)ptp_750d_get_op_root();
}

static int ptp_750d_list_sane(struct ptp_750d_op_root *root)
{
    if (!root)
    {
        return 0;
    }

    if (!root->head.next || !root->head.prev)
    {
        return 0;
    }

    return 1;
}

static uint32_t ptp_750d_manual_register(uint32_t id, void *handler)
{
    struct ptp_750d_op_root *root = ptp_750d_get_op_root();
    struct ptp_750d_op_node *head;
    struct ptp_750d_op_node *node;
    int guard;

    ptp_register_root_last = (uint32_t)root;
    ptp_register_last_id = id;

    if (!ptp_750d_list_sane(root))
    {
        return 0xdead1001;
    }

    if (!handler)
    {
        return 0xdead1002;
    }

    head = &root->head;

    /* Duplicate/update path: Canon AddListOperationFunction updates +0x0c. */
    node = head->next;
    for (guard = 0; node && node != head && guard < 512; guard++)
    {
        if (node->id == (uint16_t)id)
        {
            node->handler = handler;
            ptp_register_last_node = (uint32_t)node;
            return 0;
        }
        node = node->next;
    }

    if (guard >= 512 || !node)
    {
        return 0xdead1003;
    }

    node = malloc(sizeof(*node));
    if (!node)
    {
        return 0xdead1004;
    }

    node->id = (uint16_t)id;
    node->unk_0x0a = 0;
    node->handler = handler;

    /* Same topology Canon uses: circular doubly-linked list after head. */
    node->next = head->next;
    node->prev = head;
    head->next->prev = node;
    head->next = node;

    ptp_register_last_node = (uint32_t)node;
    return 0;
}

static void ptp_750d_do_register(void)
{
    uint32_t ret = 0;
    extern struct ptp_handler _ptp_handlers_start[];
    extern struct ptp_handler _ptp_handlers_end[];
    struct ptp_handler *handler;

    ptp_register_attempts++;
    ptp_register_root_last = ptp_750d_get_op_list_root();

    if (!ptp_register_root_last)
    {
        ptp_register_ret = 0xdead0001;
        return;
    }

    for (handler = _ptp_handlers_start; handler < _ptp_handlers_end; handler++)
    {
        void *h = handler->handler;
#ifdef CONFIG_MODULES
        h = PIC_RESOLVE(h);
#endif
        ret |= ptp_750d_manual_register(handler->id, h);
        if (ret)
        {
            break;
        }
    }

    ptp_register_ret = ret;
    if (!ret)
    {
        ptp_register_runs++;
    }
}

static void ptp_register_menu_select(void *priv, int delta)
{
    /* Safe now: no Canon ptp_register_handler() call from ML/menu context. */
    ptp_750d_do_register();
}

static void ptp_register_menu_update(struct menu_entry *entry, struct menu_display_info *info)
{
    uint32_t root = ptp_750d_get_op_list_root();

    ptp_register_root_last = root;
    MENU_SET_VALUE("runs:%d try:%d", ptp_register_runs, ptp_register_attempts);
    MENU_SET_RINFO("ret:%x root:%x id:%x node:%x", ptp_register_ret, root, ptp_register_last_id, ptp_register_last_node);
    MENU_SET_HELP("750D PTP: manual list insert; no Canon register wrapper call.");
}

static struct menu_entry ptp_debug_menu[] =
{
    {
        .name = "PTP register",
        .select = ptp_register_menu_select,
        .update = ptp_register_menu_update,
        .icon_type = IT_ACTION,
        .help = "PTP CHDK manual list registration diagnostic/retry.",
    },
};

#ifdef CONFIG_PTP_MANUAL_MENU
static void ptp_menu_init(void *unused)
{
    menu_add("Debug", ptp_debug_menu, COUNT(ptp_debug_menu));
}

INIT_FUNC("ptp_menu", ptp_menu_init);
#endif

static void ptp_750d_register_task(void *unused)
{
    int i;

    msleep(2000);

    for (i = 0; i < 120; i++)
    {
        uint32_t root = ptp_750d_get_op_list_root();
        ptp_register_root_last = root;

        if (root)
        {
            ptp_750d_do_register();
            return;
        }

        msleep(500);
    }

    ptp_register_ret = 0xdead0003;
}

TASK_CREATE("ptp_reg", ptp_750d_register_task, 0, 0x1c, 0x2000);

#else

static void ptp_init(void *unused)
{
#ifndef CONFIG_40D
    ptp_register_all_handlers();
#endif
}

#ifndef CONFIG_PTP_NO_AUTO_INIT
INIT_FUNC(__FILE__, ptp_init);
#endif

#endif
