#ifndef LED_H_
#define LED_H_

#include <avr/io.h>
#include <stdint.h>

#define LED_PORT PORTD
#define LED_DDR  DDRD

typedef struct
{
    volatile uint8_t *port; // LED가 연결된 PORT 레지스터 주소
    uint8_t pin;            // 제어할 비트 번호: 0~7
} LED;

void ledInit(LED *led);
void ledOn(LED *led);
void ledOff(LED *led);

#endif /* LED_H_ */
