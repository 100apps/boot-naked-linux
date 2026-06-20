#include <stdio.h>
#include <stdlib.h>
#include <sys/reboot.h>

int main(int argc, char **argv) {
    fprintf(stderr, "Hello from init.c!\n");
    reboot(RB_POWER_OFF);
}
