#include "i2c_lcd.h"

extern I2C_HandleTypeDef hi2c1;

/*
	LCD에 화면 지우기, 커서 이동 등의 '제어 명령(Command)'을 보내는 함수
	8비트 데이터를 4비트씩 두 번(High/Low Nibble)에 걸쳐서 쪼개 보냄 (RS 핀 = 0)
*/
void lcd_command(uint8_t command)
{
    uint8_t high_nibble, low_nibble;
    uint8_t i2c_buffer[4];

    /* 상위 4비트와 하위 4비트를 분리 */
    high_nibble = command & 0xf0;
    low_nibble = (command << 4) & 0xf0;

    /* Enable(E) 핀을 펄스(High -> Low) 형태로 만들어 데이터를 밀어 넣음 */
    i2c_buffer[0] = high_nibble | 0x04 | 0x08;
    i2c_buffer[1] = high_nibble | 0x00 | 0x08;
    i2c_buffer[2] = low_nibble  | 0x04 | 0x08;
    i2c_buffer[3] = low_nibble  | 0x00 | 0x08;

    HAL_I2C_Master_Transmit(&hi2c1, I2C_LCD_ADDRESS, i2c_buffer, 4, 10);
}

/*
	LCD에 실제로 화면에 보여질 '글자 데이터(Data)'를 보내는 함수
	명령어를 보낼 때와 거의 같지만, RS 핀의 값을 1로 설정하여 글자임을 알려줌
*/
void lcd_data(uint8_t data)
{
    uint8_t high_nibble, low_nibble;
    uint8_t i2c_buffer[4];

    /* 상위 4비트와 하위 4비트를 분리 */
    high_nibble = data & 0xf0;
    low_nibble = (data << 4) & 0xf0;

    /* RS=1(0x01)을 추가하여 데이터 모드로 전송 */
    i2c_buffer[0] = high_nibble | 0x05 | 0x08;
    i2c_buffer[1] = high_nibble | 0x01 | 0x08;
    i2c_buffer[2] = low_nibble  | 0x05 | 0x08;
    i2c_buffer[3] = low_nibble  | 0x01 | 0x08;

    HAL_I2C_Master_Transmit(&hi2c1, I2C_LCD_ADDRESS, i2c_buffer, 4, 10);
}

/*
	전원이 켜졌을 때 LCD 모듈과 I2C 칩을 초기 설정하는 함수
	이 함수는 시스템이 처음 켜질 때(while 루프 진입 전) 딱 한 번만 실행됨
	예외적으로 블로킹 함수인 HAL_Delay를 사용해도 안전
*/
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

/*
	여러 글자로 이루어진 문자열을 받아서 한 글자씩 차례대로 화면에 찍어주는 함수
	널(NULL, '\0') 문자를 만날 때까지 반복
*/
void lcd_string(char *str)
{
    while(*str) lcd_data(*str++);
}

/*
	화면에서 글자가 찍힐 위치(커서)를 원하는 행(row)과 열(col)로 이동시키는 함수
	row는 0 또는 1 (1번째, 2번째 줄), col은 0~15 사이의 위치를 가짐
*/
void move_cusor(uint8_t row, uint8_t col)
{
    lcd_command(0x80 | row << 6 | col);
}
