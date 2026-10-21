#include "lcd_4bit.h"

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
    HAL_Delay(1);
    HAL_GPIO_WritePin(LCD_E_GPIO, LCD_E_PIN, GPIO_PIN_SET);
    HAL_Delay(1);
    HAL_GPIO_WritePin(LCD_E_GPIO, LCD_E_PIN, GPIO_PIN_RESET);
    HAL_Delay(2);
}

void LCD_SentByte(uint8_t data)
{
    LCD_Data4Bit((uint8_t)(data & 0xF0U));
    LCD_EnablePin();
    LCD_Data4Bit((uint8_t)((data << 4) & 0xF0U));
    LCD_EnablePin();
}

void LCD_WriteCommand(uint8_t commandData)
{
    HAL_GPIO_WritePin(LCD_RS_GPIO, LCD_RS_PIN, GPIO_PIN_RESET);
    LCD_SentByte(commandData);
}

void LCD_WriteData(uint8_t charData)
{
    HAL_GPIO_WritePin(LCD_RS_GPIO, LCD_RS_PIN, GPIO_PIN_SET);
    LCD_SentByte(charData);
}

void LCD_GotoXY(uint8_t row, uint8_t col)
{
    uint8_t addr;

    if (row > 1U)
    {
        row = 1U;
    }

    if (col > 15U)
    {
        col = 15U;
    }

    addr = (row == 0U) ? col : (uint8_t)(0x40U + col);
    LCD_WriteCommand((uint8_t)(0x80U | addr));
}

void LCD_WriteString(char *string)
{
    while (*string)
    {
        LCD_WriteData((uint8_t)*string++);
    }
}

void LCD_WriteStringXY(uint8_t row, uint8_t col, char *string)
{
    LCD_GotoXY(row, col);
    LCD_WriteString(string);
}

void LCD_Init(void)
{
    HAL_Delay(50);

    /* 실제 학습 화면의 원본 값입니다. LCD_Data4Bit()의 Bit 해석과 불일치합니다. */
    LCD_Data4Bit(0x03U);
    LCD_EnablePin();
    HAL_Delay(5);

    LCD_Data4Bit(0x03U);
    LCD_EnablePin();
    HAL_Delay(1);

    LCD_Data4Bit(0x03U);
    LCD_EnablePin();
    LCD_Data4Bit(0x02U);
    LCD_EnablePin();

    LCD_WriteCommand(0x28U);
    LCD_WriteCommand(0x0CU); /* 원본 주석: Display Off */
    LCD_WriteCommand(0x01U);
    LCD_WriteCommand(0x06U);
}
