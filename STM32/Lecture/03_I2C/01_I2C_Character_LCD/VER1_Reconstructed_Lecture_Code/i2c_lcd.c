/*
 * i2c_lcd.c
 *
 *  Reconstructed from the lecture screenshots dated 2026. 5. 21.
 */

#include "i2c_lcd.h"

void lcd_command(uint8_t command)
{
    uint8_t high_nibble, low_nibble;
    uint8_t i2c_buffer[4];

    high_nibble = command & 0xF0;
    low_nibble = (command << 4) & 0xF0;

    /* P7-P4: DB7-DB4, P3: Backlight, P2: E, P1: R/W, P0: RS */
    i2c_buffer[0] = high_nibble | 0x04 | 0x08; /* Enable = 1, RS = 0, RW = 0 */
    i2c_buffer[1] = high_nibble | 0x00 | 0x08; /* Enable = 0, RS = 0, RW = 0 */
    i2c_buffer[2] = low_nibble  | 0x04 | 0x08; /* Enable = 1, RS = 0, RW = 0 */
    i2c_buffer[3] = low_nibble  | 0x00 | 0x08; /* Enable = 0, RS = 0, RW = 0 */

    while (HAL_I2C_Master_Transmit(&hi2c1, I2C_LCD_ADDRESS,
                                   i2c_buffer, 4, 100) != HAL_OK)
    {
        /* HAL_Delay(1); */
    }
}

void lcd_data(uint8_t data)
{
    uint8_t high_nibble, low_nibble;
    uint8_t i2c_buffer[4];

    high_nibble = data & 0xF0;
    low_nibble = (data << 4) & 0xF0;

    i2c_buffer[0] = high_nibble | 0x05 | 0x08; /* Enable = 1, RS = 1, RW = 0 */
    i2c_buffer[1] = high_nibble | 0x01 | 0x08; /* Enable = 0, RS = 1, RW = 0 */
    i2c_buffer[2] = low_nibble  | 0x05 | 0x08; /* Enable = 1, RS = 1, RW = 0 */
    i2c_buffer[3] = low_nibble  | 0x01 | 0x08; /* Enable = 0, RS = 1, RW = 0 */

    while (HAL_I2C_Master_Transmit(&hi2c1, I2C_LCD_ADDRESS,
                                   i2c_buffer, 4, 100) != HAL_OK)
    {
        /* HAL_Delay(1); */
    }
}

void i2c_lcd_init()
{
    HAL_Delay(50);

    lcd_command(0x33);
    HAL_Delay(5);
    lcd_command(0x32);
    HAL_Delay(5);
    lcd_command(0x28);
    HAL_Delay(5);
    lcd_command(DISPLAY_ON);
    HAL_Delay(5);
    lcd_command(0x06);
    HAL_Delay(5);
    lcd_command(CLEAR_DISPLAY);
    HAL_Delay(2);
}

void lcd_string(char *str)
{
    while (*str)
    {
        lcd_data(*str++);
    }
}

void move_cusor(uint8_t row, uint8_t col)
{
    lcd_command(0x80 | row << 6 | col);
}
