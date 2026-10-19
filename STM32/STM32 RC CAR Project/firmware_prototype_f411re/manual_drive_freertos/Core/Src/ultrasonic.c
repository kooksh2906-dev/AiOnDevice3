/*
 * ultrasonic.c
 *
 *  Created on: 2026. 6. 4.
 *      Author: user
 */

#include "ultrasonic.h"

/* * 각각의 센서를 독립적인 구조체 변수로 선언 및 초기화
 * (상태 변수들은 자동으로 0으로 초기화됨)
 */
Ultrasonic_Control US_LEFT = {
    TRIG_LEFT_PORT, TRIG_LEFT_PIN, TIM_CHANNEL_1, TIM_IT_CC1, HAL_TIM_ACTIVE_CHANNEL_1
};

Ultrasonic_Control US_FRONT = {
    TRIG_FRONT_PORT, TRIG_FRONT_PIN, TIM_CHANNEL_2, TIM_IT_CC2, HAL_TIM_ACTIVE_CHANNEL_2
};

Ultrasonic_Control US_RIGHT = {
    TRIG_RIGHT_PORT, TRIG_RIGHT_PIN, TIM_CHANNEL_3, TIM_IT_CC3, HAL_TIM_ACTIVE_CHANNEL_3
};

/* 순차 스캔을 위한 센서 포인터 배열 */
Ultrasonic_Control* us_list[3] = {&US_LEFT, &US_FRONT, &US_RIGHT};

/**
  * @brief  구조체 포인터를 받아 해당 센서를 구동하는 함수
  */
void Ultrasonic_Trigger(Ultrasonic_Control *us)
{
    // 안전을 위해 널 포인터 검사
    if (us == NULL) return;

    // 해당 구조체 안의 상태 변수 조작
    us->captureFlag = 0;
    __HAL_TIM_SET_CAPTUREPOLARITY(&htim3, us->tim_channel, TIM_INPUTCHANNELPOLARITY_RISING);

    // 트리거 신호 발생
    HAL_GPIO_WritePin(us->trig_port, us->trig_pin, GPIO_PIN_SET);
    delay_us(10);
    HAL_GPIO_WritePin(us->trig_port, us->trig_pin, GPIO_PIN_RESET);

    // 인터럽트 활성화
    __HAL_TIM_ENABLE_IT(&htim3, us->tim_it_cc);
}

/**
  * @brief  전체 센서 스캔, Non-blocking 실시간 센서 스캐너
  */
void Ultrasonic_Scan_ALL(void){

	static uint32_t last_scan_time = 0;
	static uint8_t  sensor_idx = 0;
	uint32_t current_time = HAL_GetTick(); // 시스템 타이머(1ms 단위) 읽기

	// 마지막으로 쏜 지 30ms가 지났을 때만 다음 센서 격발
	if (current_time - last_scan_time >= 30)
	{
		Ultrasonic_Trigger(us_list[sensor_idx]);

		sensor_idx++;
		if(sensor_idx >= 3) sensor_idx = 0; // 0->1->2 순환

		last_scan_time = current_time; // 시간 갱신
	}
}

/**
  * @brief  인풋 캡처 인터럽트 콜백
  */
void HAL_TIM_IC_CaptureCallback(TIM_HandleTypeDef *htim)
{
    if(htim->Instance == TIM3)
    {
        // 현재 인터럽트가 발생한 채널을 담당하는 센서의 포인터를 찾음
        Ultrasonic_Control *active_us = NULL;

        if (htim->Channel == US_LEFT.active_channel)       active_us = &US_LEFT;
        else if (htim->Channel == US_FRONT.active_channel) active_us = &US_FRONT;
        else if (htim->Channel == US_RIGHT.active_channel) active_us = &US_RIGHT;

        // 일치하는 센서가 없으면 탈출
        if (active_us == NULL) return;

        // State 0: Rising Edge
        if(active_us->captureFlag == 0)
        {
            active_us->IC_Value1 = HAL_TIM_ReadCapturedValue(&htim3, active_us->tim_channel);
            active_us->captureFlag = 1;
            __HAL_TIM_SET_CAPTUREPOLARITY(&htim3, active_us->tim_channel, TIM_INPUTCHANNELPOLARITY_FALLING);
        }
        // State 1: Falling Edge
        else if(active_us->captureFlag == 1)
        {
            active_us->IC_Value2 = HAL_TIM_ReadCapturedValue(&htim3, active_us->tim_channel);

            uint16_t echoTime = 0;
            if(active_us->IC_Value2 >= active_us->IC_Value1)
            {
                echoTime = active_us->IC_Value2 - active_us->IC_Value1;
            }
            else // 타이머 오버플로우
            {
                echoTime = (0xFFFF - active_us->IC_Value1) + active_us->IC_Value2 + 1;
            }

            // 거리 계산 후 구조체 내부의 distance에 저장!
            active_us->distance = echoTime / 58;
            active_us->captureFlag = 0;

            __HAL_TIM_SET_CAPTUREPOLARITY(&htim3, active_us->tim_channel, TIM_INPUTCHANNELPOLARITY_RISING);
            __HAL_TIM_DISABLE_IT(&htim3, active_us->tim_it_cc);
        }
    }
}
