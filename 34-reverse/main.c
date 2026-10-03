#include <stdio.h>

extern const char init_a[];
extern const char init_b[];
extern const char init_c[];

int main(void)
{
    printf("%s %s %s\n", init_a, init_b, init_c);
    return 0;
}

