#ifndef LED_H_
#define LED_H_

#include <avr/io.h>
#include <stdint.h>

typedef struct
{
    volatile uint8_t *ddr;  // 데이터 방향 레지스터 주소
    volatile uint8_t *port; // 출력 데이터 레지스터 주소
    uint8_t pin;            // 제어할 비트 번호: 0~7
} LED;

void ledInit(LED *led);
void ledOn(LED *led);
void ledOff(LED *led);

#endif /* LED_H_ */
