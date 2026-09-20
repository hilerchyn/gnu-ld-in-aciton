typedef void (*handler_t)(void);
void reset_handler(void)
{
}

void irq_handler(void)
{
}

__attribute__((section(".isr_vector")))
handler_t vector_table[] =
{
	reset_handler,
	irq_handler,
};
