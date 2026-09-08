static int used_function(void)
{
	return 40;
}

static int unused_function(void)
{
	return 1000;
}

int main(void)
{
	return used_function() + 2;
}

