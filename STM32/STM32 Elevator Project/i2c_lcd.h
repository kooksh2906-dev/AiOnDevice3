#ifndef INC_I2C_LCD_H_
#define INC_I2C_LCD_H_

#include "main.h"

#define I2C_LCD_ADDRESS     (0x27<<1)

#define DISPLAY_ON          0x0C    /* 화면 켜기 */
#define DISPLAY_OFF         0x08    /* 화면 끄기 */
#define CLEAR_DISPLAY       0x01    /* 화면의 모든 글자를 지우고 빈 화면으로 만들기 */
#define RETURN_HOME         0x02    /* 커서를 화면의 맨 처음(0행 0열)으로 돌려보내기 */

/* LCD에 제어 명령(설정, 화면 지우기 등)을 보내는 함수 */
void lcd_command(uint8_t command);

/* LCD에 실제로 화면에 보여질 글자 1개(데이터)를 보내는 함수 */
void lcd_data(uint8_t data);

/* I2C LCD를 처음 켰을 때 통신을 준비하고 화면을 초기화하는 함수 */
void i2c_lcd_init();

/* 여러 글자로 이루어진 문장(문자열)을 한 번에 LCD에 출력하는 함수 */
void lcd_string(char *str);

/* LCD 화면에서 글자가 찍힐 위치(행, 열)를 지정하는 함수 */
void move_cusor(uint8_t row, uint8_t col);

#endif /* INC_I2C_LCD_H_ */
