#ifndef INC_BUTTON_H_
#define INC_BUTTON_H_

#include "main.h"
#include <stdbool.h>

typedef struct
{
    GPIO_TypeDef    *port;		// 버튼이 연결된 MCU의 GPIO 포트
    uint16_t        pinNumber;	// 버튼이 연결된 MCU의 핀 번호
    GPIO_PinState   onState;	// 버튼이 눌렸다고 판정할 전기적 상태
}BUTTON_CONTROL;


bool buttonGetPressed(uint8_t num);


#endif /* INC_BUTTON_H_ */
