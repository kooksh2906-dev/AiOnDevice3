#include "led.h"

/*
 * 단일 LED의 하드웨어 연결 정보와 켜짐/꺼짐 기준 전압을 담아두는 구조체입니다.
 * 핀마다 제어 방식이 다를 수 있는 점을 고려하여 on/off 상태 신호를 직접 지정하도록 설계되었습니다.
 */
typedef struct
{
    GPIO_TypeDef  *port;      /* LED가 연결된 MCU 포트 (예: GPIOC) */
    uint16_t      pinNumber;  /* LED가 연결된 MCU 핀 번호 (예: GPIO_PIN_0) */
    GPIO_PinState onState;    /* LED를 켤 때 출력할 신호 (HIGH) */
    GPIO_PinState offState;   /* LED를 끌 때 출력할 신호 (LOW) */
} LED_CONTROL;

/*
 * 8개의 LED에 대한 실제 하드웨어 핀 맵핑 배열입니다.
 * 외부 파일에서 함부로 이 배열의 값을 바꾸지 못하도록 static 키워드를 사용하여 안전하게 보호합니다.
 */
static LED_CONTROL led[8] =
{
    {GPIOC, GPIO_PIN_0,  GPIO_PIN_SET, GPIO_PIN_RESET}, /* 인덱스 0: 1번째 LED */
    {GPIOC, GPIO_PIN_1,  GPIO_PIN_SET, GPIO_PIN_RESET}, /* 인덱스 1: 2번째 LED */
    {GPIOB, GPIO_PIN_0,  GPIO_PIN_SET, GPIO_PIN_RESET}, /* 인덱스 2: 3번째 LED */
    {GPIOA, GPIO_PIN_4,  GPIO_PIN_SET, GPIO_PIN_RESET}, /* 인덱스 3: 4번째 LED */
    {GPIOA, GPIO_PIN_1,  GPIO_PIN_SET, GPIO_PIN_RESET}, /* 인덱스 4: 5번째 LED */
    {GPIOA, GPIO_PIN_0,  GPIO_PIN_SET, GPIO_PIN_RESET}, /* 인덱스 5: 6번째 LED */
    {GPIOB, GPIO_PIN_5,  GPIO_PIN_SET, GPIO_PIN_RESET}, /* 인덱스 6: 7번째 LED */
    {GPIOA, GPIO_PIN_10, GPIO_PIN_SET, GPIO_PIN_RESET}  /* 인덱스 7: 8번째 LED */
};

/*
 * 전달받은 인덱스(active_index)에 해당하는 딱 1개의 LED만 켜고, 나머지 7개는 모두 끄는 함수입니다.
 * 만약 -1과 같이 0~7 범위를 벗어난 값이 파라미터로 들어오면, 조건에 맞는 LED가 없으므로 8개 모두 꺼지게 됩니다.
 */
void LED_Update(int8_t active_index)
{
    /* 0번부터 7번까지 총 8개의 LED를 하나씩 순서대로 검사합니다. */
    for (uint8_t i = 0; i < 8; i++)
    {
        /* 현재 반복 순서(i)가 불을 켜야 할 위치(active_index)와 정확히 일치할 때 */
        if (i == active_index)
        {
            /* 해당 LED 핀에 켜짐(onState) 신호를 출력합니다. */
            HAL_GPIO_WritePin(led[i].port, led[i].pinNumber, led[i].onState);
        }
        /* 불을 켜야 할 위치가 아닐 때 */
        else
        {
            /* 해당 LED 핀에 꺼짐(offState) 신호를 출력하여 잔불이 남지 않게 합니다. */
            HAL_GPIO_WritePin(led[i].port, led[i].pinNumber, led[i].offState);
        }
    }
}
