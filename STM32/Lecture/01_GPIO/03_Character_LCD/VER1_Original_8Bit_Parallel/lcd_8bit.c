#include "lcd_8bit.h"

void LCD_Data(uint8_t data)
{
    HAL_GPIO_WritePin(LCD_D0_GPIO, LCD_D0_PIN, (data & 0x01U) ? GPIO_PIN_SET : GPIO_PIN_RESET);
    HAL_GPIO_WritePin(LCD_D1_GPIO, LCD_D1_PIN, (data & 0x02U) ? GPIO_PIN_SET : GPIO_PIN_RESET);
    HAL_GPIO_WritePin(LCD_D2_GPIO, LCD_D2_PIN, (data & 0x04U) ? GPIO_PIN_SET : GPIO_PIN_RESET);
    HAL_GPIO_WritePin(LCD_D3_GPIO, LCD_D3_PIN, (data & 0x08U) ? GPIO_PIN_SET : GPIO_PIN_RESET);
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

void LCD_WriteCommand(uint8_t commandData)
{
    HAL_GPIO_WritePin(LCD_RS_GPIO, LCD_RS_PIN, GPIO_PIN_RESET);
    LCD_Data(commandData);
    LCD_EnablePin();
}

void LCD_WriteData(uint8_t charData)
{
    HAL_GPIO_WritePin(LCD_RS_GPIO, LCD_RS_PIN, GPIO_PIN_SET);
    LCD_Data(charData);
    LCD_EnablePin();
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
    LCD_WriteCommand(0x38U);
    HAL_Delay(5);
    LCD_WriteCommand(0x38U);
    HAL_Delay(5);
    LCD_WriteCommand(0x38U);
    LCD_WriteCommand(0x38U);
    LCD_WriteCommand(0x0CU); /* 원본 주석: Display OFF */
    LCD_WriteCommand(0x01U); /* Display Clear */
    LCD_WriteCommand(0x06U); /* Entry Mode Set */
}
