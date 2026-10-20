#ifndef USART0_H_
#define USART0_H_

#include <stdbool.h>
#include <stdint.h>

typedef enum
{
    USART0_RX_OK = 0U,
    USART0_RX_FRAME_ERROR = (1U << 0U),
    USART0_RX_DATA_OVERRUN = (1U << 1U),
    USART0_RX_PARITY_ERROR = (1U << 2U)
} Usart0RxStatus;

typedef struct
{
    uint8_t data;
    uint8_t status;
} Usart0RxResult;

void usart0InitDoubleSpeed8N1(uint16_t ubrrValue);
bool usart0TryTransmit(uint8_t data);
void usart0TransmitBlocking(uint8_t data);
void usart0TransmitStringBlocking(const char *text);
bool usart0TryReceive(Usart0RxResult *result);
Usart0RxResult usart0ReceiveBlocking(void);

#endif /* USART0_H_ */
