#include "pwm1.h"

#include <avr/io.h>
#include <stdint.h>

#define TIMER1_CLOCK_HZ       16000000UL
#define TIMER1_PRESCALER      64UL
#define TIMER1_PWM_HZ         50UL
#define TIMER1_MIN_PULSE_US   500U
#define TIMER1_MAX_PULSE_US   2500U

void pwm1Init50Hz(void)
{
    DDRB |= (1U << PB5);

    // Clock를 연결하기 전에 Mode와 출력 동작을 먼저 설정한다.
    TCCR1A = (1U << COM1A1) | (1U << WGM11);
    TCCR1B = (1U << WGM13) | (1U << WGM12);
    TCCR1C = 0U;

    TCNT1 = 0U;

    // 16 MHz / (64 × 50 Hz) - 1 = 4999
    ICR1 = (uint16_t)(TIMER1_CLOCK_HZ /
                      (TIMER1_PRESCALER * TIMER1_PWM_HZ) - 1UL);

    // 시작 Pulse를 1.5 ms로 설정한다.
    pwm1SetPulseUs(1500U);

    // CS12:0=011로 64분주 Clock를 연결하여 Timer를 시작한다.
    TCCR1B |= (1U << CS11) | (1U << CS10);
}

void pwm1SetPulseUs(uint16_t pulseWidthUs)
{
    if (pulseWidthUs < TIMER1_MIN_PULSE_US)
    {
        pulseWidthUs = TIMER1_MIN_PULSE_US;
    }
    else if (pulseWidthUs > TIMER1_MAX_PULSE_US)
    {
        pulseWidthUs = TIMER1_MAX_PULSE_US;
    }

    /*
     * 16 MHz / 64 = 250 kHz이므로 Timer Tick은 4 us이다.
     * 반올림한 Count에서 1을 빼 OCR1A 값을 만든다.
     */
    const uint32_t timerClockHz = TIMER1_CLOCK_HZ / TIMER1_PRESCALER;
    const uint32_t pulseCounts =
        ((uint32_t)pulseWidthUs * timerClockHz + 500000UL) / 1000000UL;

    OCR1A = (uint16_t)(pulseCounts - 1UL);
}
