#include <avr/io.h>
#include <stdint.h>

#define UART0_UBRR_9600_U2X 207U

static void uart0Init(void)
{
    UCSR0B = 0x00U;
    UCSR0A = (1U << U2X0);
    UBRR0H = (uint8_t)(UART0_UBRR_9600_U2X >> 8U);
    UBRR0L = (uint8_t)UART0_UBRR_9600_U2X;
    UCSR0C = (1U << UCSZ01) | (1U << UCSZ00);
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

// 기초 함수 연습: Null 문자 전까지 문자열을 1 byte씩 송신한다.
static void uart0TransmitString(const char *text)
{
    while (*text != '\0')
    {
        uart0Transmit((uint8_t)*text);
        text++;
    }
}

// 심화 함수 연습: 1 byte를 상·하위 Nibble로 나누어 2자리 16진수로 출력한다.
static void uart0TransmitHex8(uint8_t data)
{
    static const char hexDigits[] = "0123456789ABCDEF";

    uart0Transmit((uint8_t)hexDigits[(data >> 4U) & 0x0FU]);
    uart0Transmit((uint8_t)hexDigits[data & 0x0FU]);
}

static uint8_t uart0ToPrintable(uint8_t data)
{
    return (data >= 0x20U && data <= 0x7EU) ? data : (uint8_t)'.';
}

int main(void)
{
    uart0Init();
    uart0TransmitString("USART0 byte monitor: 9600-8N1\r\n");

    while (1)
    {
        const uint8_t receivedData = uart0Receive();

        uart0TransmitString("RX=0x");
        uart0TransmitHex8(receivedData);
        uart0TransmitString(" CHAR=");
        uart0Transmit(uart0ToPrintable(receivedData));
        uart0TransmitString("\r\n");
    }
}
