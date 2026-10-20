#include "usart0.h"

#include <stdint.h>

#ifndef F_CPU
#define F_CPU 16000000UL
#endif

#define UART0_BAUD 9600UL
#define UART0_UBRR_VALUE \
    ((uint16_t)(((F_CPU + (4UL * UART0_BAUD)) / \
                  (8UL * UART0_BAUD)) - 1UL))

int main(void)
{
    usart0InitDoubleSpeed8N1(UART0_UBRR_VALUE);
    usart0TransmitStringBlocking("USART0 error-aware echo ready\r\n");

    while (1)
    {
        const Usart0RxResult received = usart0ReceiveBlocking();

        if (received.status == USART0_RX_OK)
        {
            usart0TransmitBlocking(received.data);
        }
        else
        {
            // 오류가 있는 Character를 그대로 Echo하지 않고 진단 Marker를 보낸다.
            usart0TransmitStringBlocking("[RX_ERROR]");
        }
    }
}
