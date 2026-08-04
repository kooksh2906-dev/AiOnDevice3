/* USER CODE END Header */

/* Define to prevent recursive inclusion -------------------------------------*/
#ifndef __MAIN_H
#define __MAIN_H

#ifdef __cplusplus
extern "C" {
#endif

/* Includes ------------------------------------------------------------------*/
#include "stm32f4xx_hal.h"

/* Private includes ----------------------------------------------------------*/
/* USER CODE BEGIN Includes */
#include <stdlib.h>
#include <stdio.h>      // printf, fflush, stdout 사용을 위해 필수
#include <string.h>     // strcmp 사용을 위해 필수
#include <stdbool.h>    // true, false (bool) 사용을 위해 필수

/* 시스템을 구성하는 각각의 부품 및 기능별 헤더 파일들 */
#include "queue.h"      /* UART 수신 데이터 처리를 위한 큐(Queue) */
#include "usart.h"      /* 시리얼 통신(UART) 설정 */
#include "door.h"       /* 엘리베이터 문(도어 모터) 제어 */
#include "stepper.h"    /* 엘리베이터 상하 이동 승강 모터 제어 */
#include "button.h"     /* 물리 버튼(상/하행) 입력 처리 */
#include "led.h"        /* 층수 표시용 8구 LED 제어 */
#include "photo.h"      /* 상하단 리밋(안전) 포토 센서 제어 */
#include "buzzer.h"     /* 경고음 및 이동 알림음 출력 */
#include "cmd.h"        /* PC 터미널 명령어(CLI) 분석 및 처리 */
#include "password.h"   /* 비밀번호 키패드 입력 및 LCD 화면 로직 */
#include "my_system.h"  /* 시스템 초기화(영점), 복구 및 개별 테스트 로직 */
/* USER CODE END Includes */

/* Exported types ------------------------------------------------------------*/
/* USER CODE BEGIN ET */
/* 엘리베이터 시스템의 현재 전체 동작 상태를 나타내는 열거형 */
typedef enum{
	STATE_NORMAL,       /* 정상 동작 상태 (평상시 모드) */
	STATE_EMERGENCY,    /* 비상 정지 상태 (비상 버튼이 눌린 직후) */
	STATE_IDLE          /* 복구 대기 상태 (사용자 명령어를 기다리는 중) */
} SYSTEM_STATE;

/* 터미널에 텍스트 메시지가 무한히 반복 출력되지 않도록 막아주는 상태 플래그 */
typedef enum{
	MSG_OFF,            /* 메시지 출력 전 (출력을 허용함) */
	MSG_ON              /* 메시지 출력 완료 (출력을 차단함) */
} MSG_STATE;

/* 시스템 흐름 및 통신 제어용 변수들 */
extern uint8_t state;               /* 현재 시스템의 동작 상태 (STATE_NORMAL 등) */
extern uint8_t EmergencyMsgflag;    /* 비상 메시지 출력 여부 기록 */
extern uint8_t RecoverMsgflag;      /* 복구 메시지 출력 여부 기록 */

/* 엘리베이터 승강 모터(stepper) 제어용 변수들 */
extern uint32_t last_motor_time;    /* 모터가 마지막으로 1스텝 구동된 시간(ms) */
extern uint8_t lift_direction;      /* 엘리베이터 이동 방향 (0:정지, 1:상승, 2:하강) */
extern int8_t motor_step;           /* 1-2상 여자 방식 배열의 현재 인덱스 (0~7) */

/* LED 층수 표시기 제어용 변수들 */
extern int8_t led_index;            /* 현재 불이 켜져 있는 LED의 위치 (0~7) */
extern uint32_t last_led_time;      /* LED 불빛이 마지막으로 이동한 시간(ms) */

/* USER CODE END ET */

/* Exported constants --------------------------------------------------------*/
/* USER CODE BEGIN EC */

/* USER CODE END EC */

/* Exported macro ------------------------------------------------------------*/
/* USER CODE BEGIN EM */

/* USER CODE END EM */

/* Exported functions prototypes ---------------------------------------------*/
void Error_Handler(void);

/* USER CODE BEGIN EFP */

/* USER CODE END EFP */

/* Private defines -----------------------------------------------------------*/

/* USER CODE BEGIN Private defines */

/* USER CODE END Private defines */

#ifdef __cplusplus
}
#endif

#endif /* __MAIN_H */
