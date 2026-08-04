#ifndef INC_I2C_LCD_H_
#define INC_I2C_LCD_H_

#include "main.h"
#include <stdint.h>

/*
 * I2C Text LCD Address
 * Most PCF8574 LCD backpacks use 0x27 or 0x3F.
 * STM32 HAL needs the 8-bit shifted address, so use (7-bit address << 1).
 */
#define I2C_LCD_ADDRESS     (0x27 << 1)

#define LCD_DISPLAY_ON      0x0C
#define LCD_DISPLAY_OFF     0x08
#define LCD_CLEAR_DISPLAY   0x01
#define LCD_RETURN_HOME     0x02

/* Backward compatibility with your original names */
#define DISPLAY_ON          LCD_DISPLAY_ON
#define DISPLAY_OFF         LCD_DISPLAY_OFF
#define CLEAR_DISPLAY       LCD_CLEAR_DISPLAY
#define RETURN_HOME         LCD_RETURN_HOME

void i2c_lcd_init(void);
void lcd_command(uint8_t command);
void lcd_data(uint8_t data);
void lcd_string(char *str);
void move_cusor(uint8_t row, uint8_t col);   /* original typo kept for compatibility */
void move_cursor(uint8_t row, uint8_t col);  /* corrected function name */

void lcd_clear(void);
void lcd_puts_xy(uint8_t row, uint8_t col, char *str);
void lcd_print_line(uint8_t row, char *str);
void lcd_show_ready(void);
void lcd_show_waiting_can(void);
void lcd_show_speed(uint16_t target_speed, uint16_t current_speed);

#endif /* INC_I2C_LCD_H_ */
