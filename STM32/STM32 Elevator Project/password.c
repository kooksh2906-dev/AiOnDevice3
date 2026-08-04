#include "password.h"
#include "keypad.h"
#include "i2c_lcd.h"
#include <string.h>

/* 정답으로 설정된 비밀번호 */
static char correct_password[] = "1234A";

/* 사용자가 누른 키패드 글자들을 모아둘 배열 (LCD 한 줄의 길이인 16글자 + 널 문자) */
static char password[17] = {0,};

/* 현재까지 입력된 비밀번호의 글자 수 (배열 인덱스로 사용) */
static uint8_t pass_index = 0;

/* 결과 메시지(Pass/Denied) 출력을 위한 비동기 타이머 변수 */
static uint32_t msg_display_time = 0;

/* 현재 결과 메시지를 화면에 띄우고 있는 중인지(1) 아닌지(0)를 나타내는 상태 플래그 */
static uint8_t showing_msg = 0;

/*
 * 시스템 시작 시 한 번 호출되어 LCD 화면을 초기화하고
 * 첫 번째 줄에 안내 문구를 띄워주는 함수입니다.
 */
void Password_Init(void)
{
    i2c_lcd_init();
    move_cusor(0, 0);
    lcd_string("Press Password  ");
}

/*
 * 메인 루프에서 지속적으로 호출되며, 키패드 입력을 감지하고
 * 비밀번호 로직을 처리하는 핵심 함수입니다.
 */
void Password_Update(void)
{
    /* 1. 결과 메세지(Pass/No Pass)를 보여주고 있는 중이라면 */
    if (showing_msg == 1)
    {
        /* 3초(3000ms)가 지났는지 확인 (HAL_Delay 대체) */
        if (HAL_GetTick() - msg_display_time >= 3000)
        {
            showing_msg = 0; /* 메세지 표시 상태 해제 */

            /* 입력 버퍼와 화면을 모두 초기화하여 다음 입력을 받을 준비를 함 */
            memset(password, 0, sizeof(password));
            pass_index = 0;
            move_cusor(1, 0);
            lcd_string("                "); /* 아래줄 지우기 */
        }
        return; /* 메세지를 보여주는 3초 동안은 키패드 입력을 무시함 */
    }

    /* 2. 평상시 키패드 입력 처리 (버튼이 방금 눌렸을 때만 문자를 반환받음) */
    char key = Keypad_Scan();

    /* 키가 눌렸을 경우 */
    if (key != 0)
    {
        /* '*' 키를 누르면 입력 중이던 비밀번호를 모두 지우고 초기화 (백스페이스/초기화 역할) */
        if (key == '*')
        {
            memset(password, 0, sizeof(password));
            pass_index = 0;
            move_cusor(1, 0);
            lcd_string("                ");
        }
        /* '#' 키를 누르면 현재까지 입력한 비밀번호를 정답과 비교 (엔터 역할) */
        else if (key == '#')
        {
            move_cusor(1, 0);

            /* strcmp를 이용해 두 문자열이 완벽히 일치하는지 비교 (일치하면 0 반환) */
            if (strcmp(password, correct_password) == 0)
            {
                lcd_string("Pass!           ");
            }
            else
            {
                lcd_string("Denied!        ");
            }

            /* [핵심] HAL_Delay(3000) 제거 -> 현재 시간 기록 후 메세지 표시 상태로 전환 */
            msg_display_time = HAL_GetTick();
            showing_msg = 1;
        }
        /* 일반 숫자/알파벳 키를 눌렀고, 16글자를 아직 안 넘었을 경우 */
        else if (pass_index < 16)
        {
            password[pass_index] = key; /* 배열에 누른 글자 추가 */
            pass_index++;

            /* LCD 아래줄을 한 번 지운 뒤, 갱신된 비밀번호 문자열을 출력 */
            move_cusor(1, 0);
            lcd_string("                "); /* 잔상 제거 */
            move_cusor(1, 0);
            lcd_string(password);
        }
    }
}
