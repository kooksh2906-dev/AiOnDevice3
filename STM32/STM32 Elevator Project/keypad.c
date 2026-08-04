#include "keypad.h"

/*
	4x4 키패드의 물리적인 버튼 배치와 똑같이 매핑된 문자 배열
	행(Row)과 열(Column) 전압이 교차하여 눌린 지점의 문자를 찾아낼 때 사용
*/
const char key_map[4][4] = {
        {'1', '2', '3', 'A'},
        {'4', '5', '6', 'B'},
        {'7', '8', '9', 'C'},
        {'*', '0', '#', 'D'}
};

GPIO_TypeDef* row_ports[4] = {GPIOC, GPIOA, GPIOA, GPIOB};
uint16_t row_pins[4]       = {GPIO_PIN_7, GPIO_PIN_9, GPIO_PIN_8, GPIO_PIN_10};

GPIO_TypeDef* col_ports[4] = {GPIOB, GPIOA, GPIOA, GPIOA};
uint16_t col_pins[4]       = {GPIO_PIN_6, GPIO_PIN_7, GPIO_PIN_6, GPIO_PIN_5};

/*
키패드를 스캔하여 현재 눌린 버튼의 문자를 반환하는 함수
메인 루프에서 계속 호출되며, 버튼을 처음 누른 그 '순간(Edge)'에만 딱 1번 문자를 반환
*/
char Keypad_Scan(void)
{
	/* static 변수를 사용하여 함수가 끝나도 이전에 눌려있던 키 상태를 계속 기억*/
    static char old_key = 0;

    /* 이번 스캔 루프에서 감지된 키 값을 임시로 저장하는 변수*/
    char current_key = 0;

    /* 4개의 행(Row)에 순차적으로 LOW 신호를 쏘면서 스캐닝을 시작*/
    for (int i = 0; i < 4; i++)
    {
    		/* 현재 검사할 1개의 행(Row)에만 전압을 낮춤 (LOW 신호 출력) */
        HAL_GPIO_WritePin(row_ports[i], row_pins[i], GPIO_PIN_RESET);

        /* 특정 행에 LOW 신호를 준 상태에서, 4개의 열(Column)을 모두 읽어봄 */
        for (int j = 0; j < 4; j++)
        {
            if (HAL_GPIO_ReadPin(col_ports[j], col_pins[j]) == GPIO_PIN_RESET)
            {
            		/* 배열의 인덱스를 교차시켜서 눌린 위치의 문자를 찾아 저장 */
                current_key = key_map[i][j];
            }
        }
        HAL_GPIO_WritePin(row_ports[i], row_pins[i], GPIO_PIN_SET);
    }

    /*
     이전 루프(old_key)에서는 아무것도 안 눌려있었는데,
     지금 루프(current_key)에서 새로운 키가 감지되었을 때 딱 1번만 문자를 반환
     */
    if (current_key != 0 && old_key == 0)
    {
    	old_key = current_key; /* 눌린 상태를 기억 (다음 루프에서 중복 반환하는 것을 막음) */
    	return current_key;    /* 실제 눌린 문자 반환 */
    }
    /* 손을 떼서 아무 키도 안 눌린 상태가 감지되면, 다음 입력을 받을 준비 */
    else if (current_key == 0)
    {
    	old_key = 0; /* 상태 초기화 */
    }
    return 0; // 누르고 있는 중이거나 안 눌렀으면 0 반환
}
