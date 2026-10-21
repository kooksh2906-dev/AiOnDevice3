#ifndef INC_LCD_8BIT_H_
#define INC_LCD_8BIT_H_

#include "main.h"

#define LCD_RS_GPIO GPIOA
#define LCD_RS_PIN  GPIO_PIN_5
#define LCD_E_GPIO  GPIOA
#define LCD_E_PIN   GPIO_PIN_7

#define LCD_D0_GPIO GPIOC
#define LCD_D0_PIN  GPIO_PIN_7
#define LCD_D1_GPIO GPIOA
#define LCD_D1_PIN  GPIO_PIN_9
#define LCD_D2_GPIO GPIOA
#define LCD_D2_PIN  GPIO_PIN_8
#define LCD_D3_GPIO GPIOB
#define LCD_D3_PIN  GPIO_PIN_10
#define LCD_D4_GPIO GPIOB
#define LCD_D4_PIN  GPIO_PIN_4
#define LCD_D5_GPIO GPIOB
#define LCD_D5_PIN  GPIO_PIN_5
#define LCD_D6_GPIO GPIOB
#define LCD_D6_PIN  GPIO_PIN_3
#define LCD_D7_GPIO GPIOA
#define LCD_D7_PIN  GPIO_PIN_10

void LCD_Data(uint8_t data);
void LCD_EnablePin(void);
void LCD_WriteCommand(uint8_t commandData);
void LCD_WriteData(uint8_t charData);
void LCD_GotoXY(uint8_t row, uint8_t col);
void LCD_WriteString(char *string);
void LCD_WriteStringXY(uint8_t row, uint8_t col, char *string);
void LCD_Init(void);

#endif /* INC_LCD_8BIT_H_ */
