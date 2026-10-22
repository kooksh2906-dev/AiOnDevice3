/*
 * i2c_lcd.h
 *
 *  Created on: 2026. 5. 21.
 *      Author: user
 */

#ifndef INC_I2C_LCD_H_
#define INC_I2C_LCD_H_

#include "main.h"

#define I2C_LCD_ADDRESS  (0x27<<1)

#define DISPLAY_ON       0x0C
#define DISPLAY_OFF      0x08
#define CLEAR_DISPLAY    0x01
#define RETURN_HOME      0x02

extern I2C_HandleTypeDef hi2c1;

void lcd_command(uint8_t command);
void lcd_data(uint8_t data);
void i2c_lcd_init();
void lcd_string(char *str);
void move_cusor(uint8_t row, uint8_t col);

#endif /* INC_I2C_LCD_H_ */
