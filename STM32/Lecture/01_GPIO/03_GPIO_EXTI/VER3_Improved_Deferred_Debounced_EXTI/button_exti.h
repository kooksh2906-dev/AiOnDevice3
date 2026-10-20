#ifndef INC_BUTTON_EXTI_H_
#define INC_BUTTON_EXTI_H_

#include "main.h"

#include <stdbool.h>

void buttonExtiInit(void);
void buttonExtiCaptureFromIsr(uint16_t GPIO_Pin);
bool buttonExtiTakePressEvent(void);

#endif /* INC_BUTTON_EXTI_H_ */
