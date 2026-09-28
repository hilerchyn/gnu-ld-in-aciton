extern int used_data;
extern int unused_data;

extern int used_function(void);
extern int unused_function(void);

int main(void)
{
    used_data++;

    return used_function();
}

