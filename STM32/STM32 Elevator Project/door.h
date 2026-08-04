#ifndef INC_DOOR_H_
#define INC_DOOR_H_

#include "main.h"

/* 스텝 모터가 1-2상 여자 방식으로 1바퀴(360도) 회전하는 데 필요한 총 스텝 수 */
#define STEPS_PER_REVOLATION    4096

/* 모터 정방향(시계 방향) 회전 값 */
#define DIR_CW                  0

/* 모터 역방향(반시계 방향) 회전 값 */
#define DIR_CCW                 1

#define IN1_DOOR_PORT   GPIOC
#define IN1_DOOR_PIN    GPIO_PIN_5   // IN1

#define IN2_DOOR_PORT   GPIOA
#define IN2_DOOR_PIN    GPIO_PIN_12    // IN2

#define IN3_DOOR_PORT   GPIOA
#define IN3_DOOR_PIN    GPIO_PIN_11      // IN3

#define IN4_DOOR_PORT   GPIOB
#define IN4_DOOR_PIN    GPIO_PIN_12      // IN4

typedef enum
{
	DOOR_IDLE,      // 정지 상태 (문이 완전히 열렸거나 닫혀서 대기 중)
	DOOR_OPENING,   // 열리는 중 (모터가 열림 방향으로 구동 중)
	DOOR_CLOSING    // 닫히는 중 (모터가 닫힘 방향으로 구동 중)
}DOOR_STATE;


typedef struct
{
	uint32_t        interval;       // 모터 구동 속도 (스텝 간 대기 시간, 보통 2ms)
	uint32_t        lastTick;       // 마지막으로 스텝을 진행한 시스템 시간(Tick) 기록
	DOOR_STATE      mode;           // 문의 현재 동작 상태 (대기/열림/닫힘)
	int32_t         currentStep;    // 문의 현재 위치 (0: 완전히 닫힘 ~ targetStep: 완전히 열림)
	uint32_t        targetStep;     // 문이 완전히 열리기 위한 목표 스텝 수 (예: 90도 = 1024)
	uint8_t         stepIdx;        // 1-2상 여자 방식 배열(HALF_STEP_SEQ)의 현재 인덱스 (0~7)
}DOOR_CONTROL;

/* 시스템 전체에서 공유하는 엘리베이터 도어 제어용 전역 구조체 인스턴스 */
extern DOOR_CONTROL elevator_door;

/*
	도어 제어 구조체 초기화 함수
	제어할 도어 구조체의 포인터
	interval: 모터 속도 제어용 틱 간격 (ms 단위)
	target: 문이 완전히 열릴 때까지 회전할 총 스텝 수
 */
void door_init(DOOR_CONTROL *door, uint32_t interval, uint32_t target);

/*
	도어 모터의 모든 핀 출력을 LOW로 설정하여 모터를 완전히 정지시키는 함수
*/
void stopMotor1(void);

/*
	지정된 인덱스에 해당하는 1-2상 여자 신호를 도어 모터 핀에 출력하는 함수
	step: 출력할 배열의 인덱스 번호 (0~7)
*/
void stepMotor1(uint8_t step);

/*
	원하는 스텝 수와 방향만큼 도어 모터를 회전시키는 함수 (블로킹 방식)
	steps: 회전시킬 스텝 수
	direction: 회전 방향 (DIR_CW 또는 DIR_CCW)
*/
void rotateSteps(uint16_t steps, uint8_t direction);

/*
	원하는 각도와 방향만큼 도어 모터를 회전시키는 함수 (블로킹 방식)
	degrees: 회전시킬 각도 (예: 90, 180)
	direction: 회전 방향 (DIR_CW 또는 DIR_CCW)
*/
void rotateDegrees(uint16_t degrees, uint8_t direction);

/*
	물리적 버튼 입력을 감지하여 도어의 동작 모드(열림/닫힘)를 변경하는 함수
	door: 상태를 변경할 도어 구조체의 포인터
*/
void process_door_input(DOOR_CONTROL *door);

/*
	설정된 interval마다 도어 모터를 1스텝씩 구동시키는 비동기 업데이트 함수
	메인 루프(while) 안에서 지속적으로 호출되어야 하며, 목표 위치에 도달하면 모터를 정지시킵니다.
	door: 구동할 도어 구조체의 포인터
*/
void updateDoor(DOOR_CONTROL *door);

#endif /* INC_DOOR_H_ */
