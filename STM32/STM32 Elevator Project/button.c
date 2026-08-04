#ifndef SRC_BUTTON_C_
#define SRC_BUTTON_C_

#include "button.h"

/*
	2개의 물리적 버튼(상행, 하행)에 대한 하드웨어 포트, 핀 번호, 눌림 판정 상태를 담은 배열
	static 키워드를 사용하여 외부 파일에서 이 변수에 직접 접근하지 못하도록 보호
*/
static BUTTON_CONTROL button[2] =
{
    {GPIOC, GPIO_PIN_10, GPIO_PIN_RESET}, /* 인덱스 0번: 1층에서 누르는 상행(Up) 버튼 */
    {GPIOC, GPIO_PIN_12, GPIO_PIN_RESET}  /* 인덱스 1번: 2층에서 누르는 하행(Down) 버튼 */
};

/*
인덱스 번호(num)를 입력받아 특정 버튼이 현재 눌려있는지 즉시 확인하는 함수
설정된 핀의 현재 상태를 읽어와서 눌림 상태(GPIO_PIN_RESET)와 일치하면 참(true)을 반환
*/
bool buttonGetPressed(uint8_t num)
{
    if(HAL_GPIO_ReadPin(button[num].port, button[num].pinNumber) == button[num].onState)
    {
        return true;
    }
    return false;
}

#endif /* SRC_BUTTON_C_ */
