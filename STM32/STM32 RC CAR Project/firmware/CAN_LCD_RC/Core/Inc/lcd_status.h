#ifndef INC_LCD_STATUS_H_
#define INC_LCD_STATUS_H_

#ifdef __cplusplus
extern "C" {
#endif

/* CAN 수신 상태를 16x2 LCD에 표시하는 FreeRTOS 태스크입니다. */
void LcdStatus_Task(void *argument);

#ifdef __cplusplus
}
#endif

#endif /* INC_LCD_STATUS_H_ */
