#include "pwm0.h"

#include <avr/io.h>
#include <util/delay.h>
#include <stdint.h>

#define PWM0_STEP_DELAY_MS 10

void pwm0Init(void)
{
    DDRB |= (1U << PB4);

    // 이전 설정에 의존하지 않도록 Fast PWM 설정을 명시적으로 대입한다.
    TCCR0 = (1U << WGM00) | (1U << COM01) |
            (1U << WGM01) | (1U << CS02);

    TCNT0 = 0U;
    OCR0 = 0U;
}

void pwm0SetCompare(uint8_t compareValue)
{
    OCR0 = compareValue;
}

void pwm0SweepUp(void)
{
    /*
     * 16-bit 반복변수를 사용하여 255까지 출력한 뒤 정상적으로 종료한다.
     * OCR0에 기록할 때만 8-bit로 변환한다.
     */
    for (uint16_t value = 0U; value <= UINT8_MAX; value++)
    {
        pwm0SetCompare((uint8_t)value);
        _delay_ms(PWM0_STEP_DELAY_MS);
    }
}

void pwm0SweepDown(void)
{
    for (uint16_t value = (uint16_t)UINT8_MAX + 1U; value > 0U; value--)
    {
        pwm0SetCompare((uint8_t)(value - 1U));
        _delay_ms(PWM0_STEP_DELAY_MS);
    }
}
