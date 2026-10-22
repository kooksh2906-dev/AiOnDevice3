/*
 * i2c_lcd.c
 *
 *  Status-checked version based on the lecture code.
 */

#include "i2c_lcd.h"

#define LCD_RS_DATA       0x01U
#define LCD_ENABLE_HIGH   0x04U
#define LCD_BACKLIGHT_ON  0x08U
#define LCD_TX_TIMEOUT_MS 100U

static HAL_StatusTypeDef i2c_lcd_write_byte(uint8_t value, uint8_t rs)
{
    uint8_t high_nibble = value & 0xF0U;
    uint8_t low_nibble = (uint8_t)((value << 4) & 0xF0U);
    uint8_t control = (uint8_t)(LCD_BACKLIGHT_ON | rs);
    uint8_t i2c_buffer[4];

    /* E High/Low를 상·하위 Nibble마다 만들어 한 번의 I2C 전송으로 보냅니다. */
    i2c_buffer[0] = (uint8_t)(high_nibble | control | LCD_ENABLE_HIGH);
    i2c_buffer[1] = (uint8_t)(high_nibble | control);
    i2c_buffer[2] = (uint8_t)(low_nibble | control | LCD_ENABLE_HIGH);
    i2c_buffer[3] = (uint8_t)(low_nibble | control);

    return HAL_I2C_Master_Transmit(&hi2c1, I2C_LCD_ADDRESS_HAL,
                                   i2c_buffer, 4U, LCD_TX_TIMEOUT_MS);
}

HAL_StatusTypeDef i2c_lcd_command(uint8_t command)
{
    HAL_StatusTypeDef status = i2c_lcd_write_byte(command, 0U);

    if (status == HAL_OK)
    {
        /* Write-only 구성에서는 Busy Flag를 읽을 수 없어 실행 시간을 확보합니다. */
        HAL_Delay((command == I2C_LCD_CLEAR_DISPLAY ||
                   command == I2C_LCD_RETURN_HOME) ? 2U : 1U);
    }

    return status;
}

HAL_StatusTypeDef i2c_lcd_data(uint8_t data)
{
    HAL_StatusTypeDef status = i2c_lcd_write_byte(data, LCD_RS_DATA);

    if (status == HAL_OK)
    {
        HAL_Delay(1U);
    }

    return status;
}

HAL_StatusTypeDef i2c_lcd_init(void)
{
    HAL_StatusTypeDef status;

    /* Address ACK를 제한된 횟수만 확인하여 무한 대기를 피합니다. */
    status = HAL_I2C_IsDeviceReady(&hi2c1, I2C_LCD_ADDRESS_HAL, 3U, 100U);
    if (status != HAL_OK)
    {
        return status;
    }

    HAL_Delay(50U);

    status = i2c_lcd_command(0x33U);
    if (status != HAL_OK) return status;
    HAL_Delay(5U);

    status = i2c_lcd_command(0x32U);
    if (status != HAL_OK) return status;
    HAL_Delay(5U);

    status = i2c_lcd_command(0x28U); /* 4-bit, 2-line, 5x8 Font */
    if (status != HAL_OK) return status;

    status = i2c_lcd_command(I2C_LCD_DISPLAY_ON);
    if (status != HAL_OK) return status;

    status = i2c_lcd_command(0x06U); /* Cursor increment, no display shift */
    if (status != HAL_OK) return status;

    return i2c_lcd_command(I2C_LCD_CLEAR_DISPLAY);
}

HAL_StatusTypeDef i2c_lcd_string(const char *str)
{
    HAL_StatusTypeDef status;

    if (str == 0)
    {
        return HAL_ERROR;
    }

    while (*str != '\0')
    {
        status = i2c_lcd_data((uint8_t)*str++);
        if (status != HAL_OK)
        {
            return status;
        }
    }

    return HAL_OK;
}

HAL_StatusTypeDef i2c_lcd_move_cursor(uint8_t row, uint8_t col)
{
    uint8_t address;

    if (row >= I2C_LCD_ROWS || col >= I2C_LCD_COLUMNS)
    {
        return HAL_ERROR;
    }

    address = (row == 0U) ? col : (uint8_t)(0x40U + col);
    return i2c_lcd_command((uint8_t)(0x80U | address));
}
