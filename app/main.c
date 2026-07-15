#include <stdio.h>
#include <bruol.h>

int main(int argc, char *argv[])
{
	(void)argc;
	(void)argv;

	printf("hello from the external rpi5 platform repo\n");
	printf("%s", BRUOL_BANNER);
	return 0;
}
