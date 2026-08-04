#include "buzzer.h"

/* '삐-삐-삐' 하는 끊어지는 패턴을 만들기 위해 200ms 주기를 재는 타이머 변수 */
static uint32_t last_buzzer_time = 0;

/* 실제 소리(주파수)를 만들기 위해 1ms마다 핀을 껐다 켜는 타이머 변수 */
static uint32_t buzzer_toggle_time = 0;

/* 현재 부저가 소리를 내야 하는 구간(ON)인지, 쉬어야 하는 구간(OFF)인지 기억하는 플래그 */
static uint8_t buzzer_is_on = 0;

void Buzzer_Update(uint8_t lift_direction)
{
    /* 엘리베이터가 위나 아래로 이동 중일 때 (0이 아닐 때) */
    if (lift_direction != 0)
    {
        /* [패턴 제어] 200ms 마다 부저의 활성/비활성 상태를 뒤집어줌 (삐- 삐- 삐- 패턴 생성) */
        if (HAL_GetTick() - last_buzzer_time >= 200)
        {
            last_buzzer_time = HAL_GetTick();
            buzzer_is_on = !buzzer_is_on; /* 0이면 1로, 1이면 0으로 스위칭 */
        }

        /* 부저 활성화 구간일 때 (소리가 나야 하는 타이밍) */
        if (buzzer_is_on)
        {
            /* [주파수 제어] 1ms 마다 핀의 전압을 HIGH/LOW로 계속 뒤집음
             * (1ms ON, 1ms OFF = 2ms 주기 = 초당 500번 진동하는 500Hz 주파수음 발생) */
            if (HAL_GetTick() - buzzer_toggle_time >= 1)
            {
                buzzer_toggle_time = HAL_GetTick();
                HAL_GPIO_TogglePin(GPIOB, GPIO_PIN_2);
            }
        }
        /* 부저 비활성화 구간일 때 (소리가 쉬어야 하는 타이밍) */
        else
        {
            /* 핀의 출력을 LOW로 고정하여 잔음이 남지 않도록 차단 */
            HAL_GPIO_WritePin(GPIOB, GPIO_PIN_2, GPIO_PIN_RESET);
        }
    }
    /* 엘리베이터가 완전히 정지했을 때 (도착 또는 대기 상태) */
    else
    {
        /* 핀 출력을 끄고, 다음 동작을 위해 상태 변수도 0으로 초기화하여 완전히 침묵시킴 */
        HAL_GPIO_WritePin(GPIOB, GPIO_PIN_2, GPIO_PIN_RESET);
        buzzer_is_on = 0;
    }
}
