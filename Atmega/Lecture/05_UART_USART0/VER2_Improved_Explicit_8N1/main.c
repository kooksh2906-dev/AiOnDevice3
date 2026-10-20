#include <avr/io.h>
#include <stdint.h>

#define UART0_UBRR_9600_U2X 207U

static void uart0Init(void)
{
    // 설정 중에는 송수신과 USART Interrupt를 모두 비활성화한다.
    UCSR0B = 0x00U;

    // Asynchronous Double Speed Mode를 명시한다.
    UCSR0A = (1U << U2X0);

    // UBRR0는 12-bit이며 High byte를 먼저, Low byte를 마지막에 기록한다.
    UBRR0H = (uint8_t)(UART0_UBRR_9600_U2X >> 8U);
    UBRR0L = (uint8_t)UART0_UBRR_9600_U2X;

    /*
     * UMSEL0=0 : Asynchronous
     * UPM01:0=00: No Parity
     * USBS0=0  : 1 Stop bit
     * UCSZ02:0=011: 8 Data bits
     * UCPOL0=0 : Asynchronous Mode에서 0
     */
    UCSR0C = (1U << UCSZ01) | (1U << UCSZ00);

    // Baud와 Frame 설정을 완료한 뒤 Receiver와 Transmitter를 활성화한다.
    UCSR0B = (1U << RXEN0) | (1U << TXEN0);
}

static void uart0Transmit(uint8_t data)
{
    while ((UCSR0A & (1U << UDRE0)) == 0U)
    {
    }

    UDR0 = data;
}

static uint8_t uart0Receive(void)
{
    while ((UCSR0A & (1U << RXC0)) == 0U)
    {
    }

    return UDR0;
}

int main(void)
{
    uart0Init();

    while (1)
    {
        uart0Transmit(uart0Receive());
    }
}
