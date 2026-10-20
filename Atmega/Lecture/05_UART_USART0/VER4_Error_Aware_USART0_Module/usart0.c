#include "usart0.h"

#include <avr/io.h>

void usart0InitDoubleSpeed8N1(uint16_t ubrrValue)
{
    UCSR0B = 0x00U;
    UCSR0A = (1U << U2X0);

    UBRR0H = (uint8_t)(ubrrValue >> 8U);
    UBRR0L = (uint8_t)ubrrValue;

    // Asynchronous, No Parity, 1 Stop bit, 8 Data bits
    UCSR0C = (1U << UCSZ01) | (1U << UCSZ00);
    UCSR0B = (1U << RXEN0) | (1U << TXEN0);
}

bool usart0TryTransmit(uint8_t data)
{
    if ((UCSR0A & (1U << UDRE0)) == 0U)
    {
        return false;
    }

    UDR0 = data;
    return true;
}

void usart0TransmitBlocking(uint8_t data)
{
    while (!usart0TryTransmit(data))
    {
    }
}

void usart0TransmitStringBlocking(const char *text)
{
    while (*text != '\0')
    {
        usart0TransmitBlocking((uint8_t)*text);
        text++;
    }
}

bool usart0TryReceive(Usart0RxResult *result)
{
    if ((UCSR0A & (1U << RXC0)) == 0U)
    {
        return false;
    }

    /*
     * FE0/DOR0/UPE0는 다음 Receive Buffer Data와 함께 유효하다.
     * UDR0를 읽으면 Buffer가 진행되므로 Status를 반드시 먼저 저장한다.
     */
    const uint8_t statusRegister = UCSR0A;
    const uint8_t receivedData = UDR0;

    result->data = receivedData;
    result->status = USART0_RX_OK;

    if ((statusRegister & (1U << FE0)) != 0U)
    {
        result->status |= USART0_RX_FRAME_ERROR;
    }

    if ((statusRegister & (1U << DOR0)) != 0U)
    {
        result->status |= USART0_RX_DATA_OVERRUN;
    }

    if ((statusRegister & (1U << UPE0)) != 0U)
    {
        result->status |= USART0_RX_PARITY_ERROR;
    }

    return true;
}

Usart0RxResult usart0ReceiveBlocking(void)
{
    Usart0RxResult result;

    while (!usart0TryReceive(&result))
    {
    }

    return result;
}
