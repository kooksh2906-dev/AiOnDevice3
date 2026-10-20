#include "fnd.h"

#include <avr/io.h>
#include <util/delay.h>
#include <stdint.h>

#define FND_STEP_MS 500

int main(void)
{
    Fnd fnd;

    // 원자료와 같은 Active-High 극성·글꼴로 시작한다.
    fndInit(&fnd, &DDRC, &PORTC,
            FND_COMMON_CATHODE, FND_FONT_LEGACY);

    while (1)
    {
        for (uint8_t digit = 0U; digit < 10U; digit++)
        {
            fndDisplayDigit(&fnd, digit);
            _delay_ms(FND_STEP_MS);
        }

        // 감소 방향에서는 Decimal Point도 함께 켠다.
        for (uint8_t digit = 9U; digit > 0U; digit--)
        {
            fndDisplayDigitWithPoint(&fnd, (uint8_t)(digit - 1U));
            _delay_ms(FND_STEP_MS);
        }

        fndClear(&fnd);
    }
}
