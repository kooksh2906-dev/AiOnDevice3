#include "pwm1.h"

#include <util/delay.h>

int main(void)
{
    pwm1Init50Hz();

    while (1)
    {
        pwm1SetPulseUs(500U);
        _delay_ms(1000);

        pwm1SetPulseUs(1500U);
        _delay_ms(1000);

        pwm1SetPulseUs(2500U);
        _delay_ms(1000);
    }
}
