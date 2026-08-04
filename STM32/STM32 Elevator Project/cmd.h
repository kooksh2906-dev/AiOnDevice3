#ifndef INC_CMD_H_
#define INC_CMD_H_

#include "main.h"

/*사용자가 터미널에 입력한 글자들을 차곡차곡 모아두는 버퍼 (최대 8글자) */
extern uint8_t cmd[8];

/* 현재 cmd 버퍼에 담긴 글자의 개수 (문자열 길이) */
extern uint8_t len;

/* 사용자가 '엔터(\r)'를 쳐서 하나의 명령어 입력이 완료되었음을 알리는 플래그 */
extern uint8_t IsCplt;

/* brief 현재 엘리베이터 시스템의 상태 (STATE_NORMAL, STATE_EMERGENCY, STATE_IDLE) */
extern uint8_t state;

/* STM32의 UART2 통신 제어 핸들 (printf 및 수신 제어용) */
extern UART_HandleTypeDef huart2;

/* "TEST RUN" 메시지가 중복 출력되지 않도록 막아주는 플래그 */
extern uint8_t TestRunMsgFlag;

/*
 	 비상 상태(STATE_EMERGENCY)에서 큐에 쌓인 데이터를 꺼내 명령어를 실행하는 함수
 	 수신된 데이터를 cmd1ByteProcess()로 넘기고, 입력이 완료되면 cmdTraceTest()를 호출
 */
void cmdExeTest();

/*
 	 복구 대기 상태(STATE_IDLE)에서 큐에 쌓인 데이터를 꺼내 명령어를 실행하는 함수
	수신된 데이터를 cmd1ByteProcess()로 넘기고, 입력이 완료되면 cmdTraceResume()을 호출
 */
void cmdExeResume();

/**
	UART로 수신된 1바이트의 문자를 분석하고 조립하는 함수
	ch: 수신된 1바이트 문자 데이터
	엔터(\r)가 입력되면 IsCplt 플래그를 켜고, 백스페이스(\b)가 입력되면 글자를 지움
 */
void cmd1ByteProcess(uint8_t ch);

/*
	비상 상태에서 완성된 명령어(cmd)를 분석하고 알맞은 동작을 수행하는 함수
	"help", "door", "move", "con" 등의 명령어를 판별하고 실행
 */
void cmdTraceTest();

/*
	복구 대기 상태에서 완성된 명령어(cmd)를 분석하고 알맞은 동작을 수행하는 함수
	시스템 재시작 여부를 묻는 질문에 대한 "y" 또는 "n" 응답을 처리
*/
void cmdTraceResume();

#endif /* INC_CMD_H_ */
