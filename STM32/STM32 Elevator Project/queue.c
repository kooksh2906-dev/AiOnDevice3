#include "queue.h"

/* UART 수신 인터럽트가 발생할 때마다 1바이트씩 받아오는 임시 저장 변수입니다. */
uint8_t usart2_rxData=0;

/* 큐에서 데이터를 꺼낼 위치(읽기 포인터)를 가리키는 변수입니다. */
uint8_t usart2_front = 0;

/* 큐에 데이터를 집어넣을 위치(쓰기 포인터)를 가리키는 변수입니다. */
uint8_t usart2_rear = 0;

/* 실제 데이터가 저장되는 원형 버퍼 배열입니다. */
uint8_t usart2_queue[USART2_QUEUE_SIZE] = {0};

/* 큐 동작의 성공/실패 여부를 직관적으로 알기 위한 상태 코드 상수들입니다. */
static const int8_t UART_ENQUEUE_OK = 0;
static const int8_t UART_ENQUEUE_ERROR_BY_FULL = -1;
const int8_t UART_DEQUEUE_OK = 0;
static const int8_t UART_DEQUEUE_ERROR_BY_EMPTY = -1;

/* * 큐를 초기화 해주는 함수
 * 읽기 위치(front)와 쓰기 위치(rear)를 모두 0으로 맞추어,
 * 큐 안에 들어있는 기존 쓰레기 데이터들을 무시하고 완전히 비우는 역할을 합니다.
 */
void queue_Flush(){

	usart2_front = 0;
	usart2_rear = 0;
}

/*
 * 큐 버퍼가 꽉 차서 더 이상 새로운 데이터를 넣을 공간이 없는지 확인하는 함수입니다.
 * 쓰기 위치(rear)의 다음 칸이 읽기 위치(front)와 만나면 꽉 찬 것으로 판정합니다.
 */
bool usart2_IsFullQueue(){

	if(((usart2_rear+1) % USART2_QUEUE_SIZE) == usart2_front)
		return true;
	else
		return false;
}

/*
 * 큐가 비어있는지 확인하는 함수입니다.
 * (참고: 현재 코드 논리상 front와 rear가 같을 때 false를 반환하고, 다를 때 true를 반환하도록 작성되어 있습니다.)
 */
bool usart2_IsEmptyQueue(){
	if(usart2_rear == usart2_front)
		return false;
	else
		return true;
}

/*
 * 큐에 새로운 데이터 1바이트를 집어넣는(EnQueue) 함수입니다.
 * 공간이 남아있다면 rear를 한 칸 이동시키고 그 위치에 데이터를 저장합니다.
 */
int8_t usart2_EnQueue(uint8_t data){

	if(usart2_IsEmptyQueue() == false)
		return UART_ENQUEUE_ERROR_BY_FULL;

	usart2_rear = (usart2_rear+1) % USART2_QUEUE_SIZE;
	usart2_queue[usart2_rear] = data;

	return UART_ENQUEUE_OK;
}

/*
 * 큐에서 가장 먼저 들어온 데이터 1바이트를 꺼내오는(DeQueue) 함수입니다.
 * 데이터가 존재하면 pdata가 가리키는 주소에 값을 복사하고 front를 한 칸 이동시킵니다.
 */
int8_t usart2_DeQueue(uint8_t* pdata){

	if(usart2_IsEmptyQueue())
		return UART_DEQUEUE_ERROR_BY_EMPTY;

	*pdata = usart2_queue[usart2_front];
	usart2_front = (usart2_front+1) % USART2_QUEUE_SIZE;

	return UART_DEQUEUE_OK;
}

/*
 * STM32 HAL 라이브러리에서 UART 데이터 수신이 완료될 때마다 자동으로 호출되는 인터럽트 콜백 함수입니다.
 * 수신된 1바이트를 큐에 밀어넣고, 다음 데이터를 받기 위해 인터럽트를 다시 활성화합니다.
 */
void HAL_UART_RxCpltCallback(UART_HandleTypeDef *huart){

	if(huart->Instance == USART2){
		/* 수신된 데이터를 큐에 삽입 (에러 발생 시 처리 구역 포함) */
		if(usart2_EnQueue(usart2_rxData) != UART_ENQUEUE_OK){
			/* Error Handling */
		}

		/* 다음 문자를 받기 위해 인터럽트를 다시 켬 */
		if(HAL_UART_Receive_IT(&huart2, &usart2_rxData, 1) != HAL_OK){
			/* Error Handling */
		}
	}
}
