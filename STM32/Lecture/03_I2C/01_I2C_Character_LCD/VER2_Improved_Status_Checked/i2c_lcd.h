/*
 * i2c_lcd.h
 *
 *  Status-checked version based on the lecture code.
 */

#ifndef INC_I2C_LCD_H_
#define INC_I2C_LCD_H_

#include "main.h"

#define I2C_LCD_ADDRESS_7BIT  0x27U
#define I2C_LCD_ADDRESS_HAL   (I2C_LCD_ADDRESS_7BIT << 1)

#define I2C_LCD_DISPLAY_ON    0x0CU
#define I2C_LCD_DISPLAY_OFF   0x08U
#define I2C_LCD_CLEAR_DISPLAY 0x01U
#define I2C_LCD_RETURN_HOME   0x02U

#define I2C_LCD_ROWS          2U
#define I2C_LCD_COLUMNS       16U

extern I2C_HandleTypeDef hi2c1;

HAL_StatusTypeDef i2c_lcd_command(uint8_t command);
HAL_StatusTypeDef i2c_lcd_data(uint8_t data);
HAL_StatusTypeDef i2c_lcd_init(void);
HAL_StatusTypeDef i2c_lcd_string(const char *str);
HAL_StatusTypeDef i2c_lcd_move_cursor(uint8_t row, uint8_t col);

#endif /* INC_I2C_LCD_H_ */
