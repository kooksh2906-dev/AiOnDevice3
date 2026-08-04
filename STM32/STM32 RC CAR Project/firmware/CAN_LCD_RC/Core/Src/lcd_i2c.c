#include "lcd_i2c.h"
#include <stdio.h>
#include <string.h>

extern I2C_HandleTypeDef hi2c1;

#define LCD_BACKLIGHT       0x08
#define LCD_ENABLE          0x04
#define LCD_RW              0x02
#define LCD_RS              0x01

#define LCD_TX_TIMEOUT      100
#define LCD_TX_RETRY        3

static HAL_StatusTypeDef lcd_i2c_write(uint8_t *data, uint16_t size);
static void lcd_write4(uint8_t data, uint8_t rs);

static HAL_StatusTypeDef lcd_i2c_write(uint8_t *data, uint16_t size)
{
    HAL_StatusTypeDef ret = HAL_ERROR;

    for (uint8_t retry = 0; retry < LCD_TX_RETRY; retry++)
    {
        ret = HAL_I2C_Master_Transmit(&hi2c1, I2C_LCD_ADDRESS, data, size, LCD_TX_TIMEOUT);

        if (ret == HAL_OK)
        {
            return HAL_OK;
        }

        HAL_Delay(1);
    }

    return ret;
}

static void lcd_write4(uint8_t data, uint8_t rs)
{
    uint8_t high_nibble = data & 0xF0;
    uint8_t low_nibble  = (data << 4) & 0xF0;
    uint8_t i2c_buffer[4];

    uint8_t control = LCD_BACKLIGHT;

    if (rs)
    {
        control |= LCD_RS;
    }

    i2c_buffer[0] = high_nibble | control | LCD_ENABLE;
    i2c_buffer[1] = high_nibble | control;
    i2c_buffer[2] = low_nibble  | control | LCD_ENABLE;
    i2c_buffer[3] = low_nibble  | control;

    lcd_i2c_write(i2c_buffer, 4);
}

void lcd_command(uint8_t command)
{
    lcd_write4(command, 0);

    if (command == LCD_CLEAR_DISPLAY || command == LCD_RETURN_HOME)
    {
        HAL_Delay(2);
    }
    else
    {
        HAL_Delay(1);
    }
}

void lcd_data(uint8_t data)
{
    lcd_write4(data, 1);
    HAL_Delay(1);
}

void i2c_lcd_init(void)
{
    HAL_Delay(50);

    /* HD44780 4-bit initialization sequence */
    lcd_command(0x33);
    HAL_Delay(5);

    lcd_command(0x32);
    HAL_Delay(5);

    lcd_command(0x28);          /* 4-bit, 2-line, 5x8 font */
    HAL_Delay(1);

    lcd_command(LCD_DISPLAY_OFF);
    HAL_Delay(1);

    lcd_command(LCD_CLEAR_DISPLAY);
    HAL_Delay(2);

    lcd_command(0x06);          /* entry mode: cursor moves right */
    HAL_Delay(1);

    lcd_command(LCD_DISPLAY_ON); /* display on, cursor off */
    HAL_Delay(1);
}

void lcd_string(char *str)
{
    while (*str)
    {
        lcd_data((uint8_t)*str++);
    }
}

void move_cusor(uint8_t row, uint8_t col)
{
    move_cursor(row, col);
}

void move_cursor(uint8_t row, uint8_t col)
{
    uint8_t address;

    if (row == 0)
    {
        address = 0x80 + col;
    }
    else
    {
        address = 0xC0 + col;
    }

    lcd_command(address);
}

void lcd_clear(void)
{
    lcd_command(LCD_CLEAR_DISPLAY);
    HAL_Delay(2);
}

void lcd_puts_xy(uint8_t row, uint8_t col, char *str)
{
    move_cursor(row, col);
    lcd_string(str);
}

void lcd_print_line(uint8_t row, char *str)
{
    char buffer[17];
    uint8_t i;

    memset(buffer, ' ', 16);
    buffer[16] = '\0';

    for (i = 0; i < 16 && str[i] != '\0'; i++)
    {
        buffer[i] = str[i];
    }

    move_cursor(row, 0);
    lcd_string(buffer);
}

void lcd_show_ready(void)
{
    lcd_print_line(0, "CAN SPEED CTRL");
    lcd_print_line(1, "LCD Ready...");
}

void lcd_show_waiting_can(void)
{
    lcd_print_line(0, "CAN SPEED CTRL");
    lcd_print_line(1, "Waiting CAN...");
}

void lcd_show_speed(uint16_t target_speed, uint16_t current_speed)
{
    char line1[17];
    char line2[17];

    snprintf(line1, sizeof(line1), "TGT:%4u RPM", target_speed);
    snprintf(line2, sizeof(line2), "CUR:%4u RPM", current_speed);

    lcd_print_line(0, line1);
    lcd_print_line(1, line2);
}
