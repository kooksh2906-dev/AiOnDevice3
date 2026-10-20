#include <avr/io.h>

int main(void)
{
    // 원자료와 같이 PORTB 전체를 출력으로 설정한다.
    DDRB = 0xFF;
    PORTB = 0x00;

    // Normal Mode, Timer0 Clock 128분주(CS02:0=101)
    TCCR0 |= (1 << CS02) | (1 << CS00);

    // 6부터 255까지 250 Count 후 Overflow한다.
    TCNT0 = 6;

    while (1)
    {
        // TOV0(bit 0)가 Set될 때까지 Polling한다.
        while ((TIFR & 0x01) == 0)
        {
        }

        // Overflow마다 PORTB 전체를 소프트웨어로 반전한다.
        PORTB ^= 0xFF;

        // 다음 Overflow 간격도 250 Count가 되도록 Preload한다.
        TCNT0 = 6;

        // TOV0는 1을 써서 해제한다.
        TIFR = 0x01;
    }
}
