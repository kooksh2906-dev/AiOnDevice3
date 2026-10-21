#include "lcd_4bit.h"

#include <stddef.h>

void LCD_Data4Bit(uint8_t data)
{
    HAL_GPIO_WritePin(LCD_D4_GPIO, LCD_D4_PIN, (data & 0x10U) ? GPIO_PIN_SET : GPIO_PIN_RESET);
    HAL_GPIO_WritePin(LCD_D5_GPIO, LCD_D5_PIN, (data & 0x20U) ? GPIO_PIN_SET : GPIO_PIN_RESET);
    HAL_GPIO_WritePin(LCD_D6_GPIO, LCD_D6_PIN, (data & 0x40U) ? GPIO_PIN_SET : GPIO_PIN_RESET);
    HAL_GPIO_WritePin(LCD_D7_GPIO, LCD_D7_PIN, (data & 0x80U) ? GPIO_PIN_SET : GPIO_PIN_RESET);
}

void LCD_EnablePin(void)
{
    HAL_GPIO_WritePin(LCD_E_GPIO, LCD_E_PIN, GPIO_PIN_RESET);
    HAL_Delay(1U);
    HAL_GPIO_WritePin(LCD_E_GPIO, LCD_E_PIN, GPIO_PIN_SET);
    HAL_Delay(1U);
    HAL_GPIO_WritePin(LCD_E_GPIO, LCD_E_PIN, GPIO_PIN_RESET);
    HAL_Delay(2U);
}

void LCD_SendByte(uint8_t data)
{
    LCD_Data4Bit((uint8_t)(data & 0xF0U));
    LCD_EnablePin();
    LCD_Data4Bit((uint8_t)((data << 4) & 0xF0U));
    LCD_EnablePin();
}

void LCD_WriteCommand(uint8_t command_data)
{
    HAL_GPIO_WritePin(LCD_RS_GPIO, LCD_RS_PIN, GPIO_PIN_RESET);
    LCD_SendByte(command_data);
}

void LCD_WriteData(uint8_t character_data)
{
    HAL_GPIO_WritePin(LCD_RS_GPIO, LCD_RS_PIN, GPIO_PIN_SET);
    LCD_SendByte(character_data);
}

void LCD_GotoXY(uint8_t row, uint8_t col)
{
    uint8_t address;

    if (row > 1U)
    {
        row = 1U;
    }

    if (col > 15U)
    {
        col = 15U;
    }

    address = (row == 0U) ? col : (uint8_t)(0x40U + col);
    LCD_WriteCommand((uint8_t)(0x80U | address));
}

void LCD_WriteString(const char *string)
{
    if (string == NULL)
    {
        return;
    }

    while (*string != 0)
    {
        LCD_WriteData((uint8_t)*string);
        ++string;
    }
}

void LCD_WriteStringXY(uint8_t row, uint8_t col, const char *string)
{
    LCD_GotoXY(row, col);
    LCD_WriteString(string);
}

void LCD_Init(void)
{
    HAL_Delay(50U);

    /* LCD_Data4Bit()가 검사하는 DB7-DB4 위치에 초기화 Nibble을 배치합니다. */
    LCD_Data4Bit(0x30U);
    LCD_EnablePin();
    HAL_Delay(5U);

    LCD_Data4Bit(0x30U);
    LCD_EnablePin();
    HAL_Delay(1U);

    LCD_Data4Bit(0x30U);
    LCD_EnablePin();
    LCD_Data4Bit(0x20U);
    LCD_EnablePin();

    LCD_WriteCommand(0x28U); /* 4-bit, 2-line, 5x8 Font */
    LCD_WriteCommand(0x0CU); /* Display ON, Cursor OFF, Blink OFF */
    LCD_WriteCommand(0x01U); /* Display Clear */
    LCD_WriteCommand(0x06U); /* Entry Mode: Increment, No Shift */
}
