#include <avr/io.h>
#include <util/delay.h>

void uart0_Init()
{
    UCSR0A |= (1 << U2X0);                   // 2배속 모드
    UCSR0B |= (1 << RXEN0) | (1 << TXEN0);  // 수신 가능, 송신 가능
    UCSR0C |= (1 << UCSZ01) | (1 << UCSZ00); // 8비트, Non-Parity, Stop 1비트
    UBRR0H |= 0;                              // 9600 bps
    UBRR0L |= 207;
}

void uart0_Transmit(char data)
{
    // UDR0 Transmit Buffer가 비워질 때까지 대기한다.
    while (!(UCSR0A & (1 << UDRE0)))
    {
    }

    UDR0 = data;
}

unsigned uart0_Receive()
{
    // Receive Buffer에 읽지 않은 Data가 들어올 때까지 대기한다.
    while (!(UCSR0A & (1 << RXC0)))
    {
    }

    return UDR0;
}

int main()
{
    uart0_Init();

    while (1)
    {
        // 수신한 1 byte를 그대로 송신하는 Polling Echo이다.
        uart0_Transmit(uart0_Receive());
    }
}
