#include "main.h"
#include "usart.h"
#include <stdbool.h>

/* 원형 큐(버퍼)의 최대 크기 설정 (데이터를 최대 5개까지 임시 보관 가능) */
#define USART2_QUEUE_SIZE 5

/* UART 수신 인터럽트가 발생할 때마다 1바이트씩 받아오는 임시 저장 변수 (외부 공유) */
extern uint8_t usart2_rxData;

/* 큐에서 데이터를 성공적으로 꺼냈을 때(DeQueue) 반환되는 성공 상태 코드 (외부 공유) */
extern const int8_t UART_DEQUEUE_OK;

/* 큐 내부에 쌓인 모든 데이터를 비우고, 읽기/쓰기 위치(Front/Rear)를 초기화하는 함수 */
void queue_Flush();

/*
	큐 버퍼가 꽉 차서 더 이상 새로운 데이터를 넣을 공간이 없는지 확인하는 함수
	반환값: true (공간 부족, 꽉 참), false (데이터를 더 넣을 여유 공간 있음)
*/
bool usart2_IsFullQueue();

/*
	큐 버퍼가 완전히 비어있어서 현재 꺼낼 데이터가 없는지 확인하는 함수
	반환값: true (꺼낼 데이터가 없음, 텅 빔), false (꺼낼 데이터가 있음)
*/
bool usart2_IsEmptyQueue();

/*
	큐에 가장 먼저 들어온 데이터 1바이트를 꺼내서 pdata가 가리키는 주소에 담아주는 함수
	성공적으로 데이터를 꺼내면 UART_DEQUEUE_OK를 반환하고,
	큐가 비어있어서 꺼내지 못하면 에러 상태 코드를 반환합니다.
*/
int8_t usart2_DeQueue(uint8_t* pdata);
