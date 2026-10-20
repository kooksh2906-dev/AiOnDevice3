#include "pwm0.h"

int main(void)
{
    pwm0Init();

    while (1)
    {
        pwm0SweepUp();
        pwm0SweepDown();
    }
}
