#ifndef INC_LCD_4BIT_H_
#define INC_LCD_4BIT_H_

#include "main.h"

#define LCD_RS_GPIO GPIOA
#define LCD_RS_PIN  GPIO_PIN_5
#define LCD_E_GPIO  GPIOA
#define LCD_E_PIN   GPIO_PIN_7
#define LCD_D4_GPIO GPIOB
#define LCD_D4_PIN  GPIO_PIN_12
#define LCD_D5_GPIO GPIOB
#define LCD_D5_PIN  GPIO_PIN_13
#define LCD_D6_GPIO GPIOB
#define LCD_D6_PIN  GPIO_PIN_14
#define LCD_D7_GPIO GPIOB
#define LCD_D7_PIN  GPIO_PIN_15

void LCD_Data4Bit(uint8_t data);
void LCD_EnablePin(void);
void LCD_SendByte(uint8_t data);
void LCD_WriteCommand(uint8_t command_data);
void LCD_WriteData(uint8_t character_data);
void LCD_GotoXY(uint8_t row, uint8_t col);
void LCD_WriteString(const char *string);
void LCD_WriteStringXY(uint8_t row, uint8_t col, const char *string);
void LCD_Init(void);

#endif /* INC_LCD_4BIT_H_ */
