#include "cmd.h"

#include <stdio.h>      // printf, fflush, stdout 사용을 위해 필수
#include <string.h>     // strcmp 사용을 위해 필수
#include <stdbool.h>    // true, false (bool) 사용을 위해 필수
#include "queue.h"      // usart2_DeQueue 등 큐 관련 함수 사용을 위해 필수
#include "usart.h"

/* 사용자가 입력한 문자를 순서대로 모아두는 버퍼 배열 (최대 8글자) */
uint8_t cmd[8] = {0};

/* 현재 cmd 버퍼에 저장된 글자의 개수 (배열의 인덱스로도 사용됨) */
uint8_t len = 0;

/* 사용자가 '엔터'를 쳐서 명령어 하나가 완성되었음을 알리는 완료 플래그 */
uint8_t IsCplt = false;


/*
	비상 정지(EMERGENCY) 상태에서 메인 루프가 반복적으로 호출하는 함수
	수신 큐(Queue)에 쌓인 데이터가 있다면 1바이트씩 꺼내서 문자를 조립하고 명령어를 실행
*/
void cmdExeTest(){
	uint8_t data = 0;

	if(usart2_DeQueue(&data) == UART_DEQUEUE_OK){
		cmd1ByteProcess(data);
		cmdTraceTest();
	}
}

/*
	복구 대기(IDLE) 상태에서 메인 루프가 반복적으로 호출하는 함수
	위와 동작 방식은 동일하며, 완료 시 IDLE 전용 분석기(cmdTraceResume)를 호출
*/
void cmdExeResume(){
	uint8_t data = 0;

	if(usart2_DeQueue(&data) == UART_DEQUEUE_OK){
		cmd1ByteProcess(data);
		cmdTraceResume();
	}
}

/*
 * 수신된 1바이트의 문자를 분석하여 명령어 배열(cmd)에 차곡차곡 담아주는 함수
 * 엔터, 백스페이스 특수 키를 처리하고 입력한 글자를 터미널 화면에 띄워줍니다.
 */
void cmd1ByteProcess(uint8_t ch){

	/* [1] 사용자가 '엔터'를 쳤을 때 */
	if(ch == '\r'){
		if(len){ /* 문자열에 글자가 하나라도 존재한다면 */
			IsCplt = true;
			cmd[len] = '\0'; /* 배열의 마지막에 널(NULL) 문자를 넣어 문자열의 끝을 알림 */
			len = 0;         /* 다음 명령어를 받기 위해 길이 인덱스 0으로 초기화 */
		}
		else{ /* 아무것도 안 치고 엔터만 쳤을 때 다시 입력창 프롬프트 띄움 */
			printf("\r\nC:\\Admin> ");
			fflush(stdout);
		}
	}
	/* [2] 사용자가 '백스페이스'를 쳤을 때 (글자 지우기) */
	else if(ch == '\b'){
		if(len<=0)
			return; /* 이미 다 지워서 지울 게 없으면 무시 */

		printf("\b \b"); /* 화면에서 글자를 지우는 마법의 문자열 (커서 뒤로 -> 공백 덮어쓰기 -> 다시 뒤로) */
		fflush(stdout);
		len--;           /* 배열 인덱스도 하나 줄여서 실제로 글자를 지움 */
	}
	/* [3] 일반적인 글자를 쳤을 때 */
	else{
		cmd[len++]=ch;  /* 배열에 글자를 저장하고 인덱스 1 증가 */
		printf("%c",ch); /* 터미널 화면에 방금 친 글자를 보여줌 (에코) */
		fflush(stdout);
	}
}

/*
	완성된 문자열(cmd)을 실제 명령어와 비교하여 동작을 수행하는 함수 (비상 상태용)
	strcmp 함수를 이용해 문자열이 정확히 일치하는지 판별
*/
void cmdTraceTest(){

	if(IsCplt){
		/* 'help': 사용 가능한 명령어 목록 출력 */
		if(!strcmp((char *)cmd,"help")){
			printf("\r\nhelp : Display Trace Command");
			printf("\r\ndoor : Checking Door System");
			printf("\r\nlift : Checking Lifting Up/Down System");
			printf("\r\ncon  : Continue To Next Command");
		}
		/* 'door': 도어 모터(열림/닫힘) 동작 점검 함수 호출 */
		else if(!strcmp((char *)cmd,"door")){
			printf("\r\nChecking Door System");
			CheckDoor();
			printf("\r\nChecking Complete");
		}
		/* 'lift': 승강 모터(상/하행) 동작 점검 함수 호출 */
		else if(!strcmp((char *)cmd,"lift")){
			printf("\r\nChecking Lifting Up/Down System");
			CheckLift();
			printf("\r\nChecking Complete");
		}
		/* 'con': 점검을 마치고 시스템 복구 대기 상태(IDLE)로 넘어감 */
		else if(!strcmp((char *)cmd,"con")){
			printf("\r\nRESUME SYSTEM? [y/n]");
			printf("\r\nC:\\Admin> ");
			fflush(stdout);

			IsCplt = false;
			state = STATE_IDLE; /* 상태 변경 */
			return; /* 아래 프롬프트를 띄우지 않고 바로 함수 종료 */
		}
		/* 등록되지 않은 엉뚱한 명령어를 쳤을 때 */
		else{
			printf("\r\nInvalid Command");
		}

		/* 명령어 실행이 끝나면 다시 입력창 프롬프트를 띄워줌 */
		printf("\r\nC:\\Admin> ");
		fflush(stdout);

		IsCplt=false; /* 명령어 처리 완료 플래그 초기화 */
	}
}

/*
	시스템을 정상 상태로 복구할지 묻는 질문에 대한 응답(y/n)을 처리하는 함수 (IDLE 상태용)
*/
void cmdTraceResume(){

	if(IsCplt){
		/* 'y' (Yes): 시스템을 완전히 정상 상태로 복구함 */
		if(!strcmp((char *)cmd,"y")){
			printf("\r\nResuming System");
			fflush(stdout);

			/* 정상 모드로 넘어가기 전, UART 수신 인터럽트를 잠시 멈춤 */
			HAL_UART_AbortReceive_IT(&huart2);

			/* 큐에 남아있는 찌꺼기 데이터 초기화 (오작동 방지) */
			queue_Flush();
			len = 0;
			cmd[0]= '\0';

			state = STATE_NORMAL; /* 시스템 정상 구동 상태로 귀환 */
		}
		/* 'n' (No): 복구를 취소하고 다시 시스템 초기화 후 비상 모드로 돌아감 */
		else if(!strcmp((char *)cmd,"n")){
			printf("\r\nRecheck Recovering System");
			SysReset(); /* 영점 다시 잡기 */

			printf("\r\nTEST RUN");
			printf("\r\nC:\\Admin> ");
			fflush(stdout);

			state = STATE_EMERGENCY; /* 비상 테스트 모드로 복귀 */
		}
		/* y나 n이 아닌 다른 글자를 쳤을 때 */
		else{
			printf("\r\nInvalid Command ");
			printf("\r\nRESUME SYSTEM? [y/n]");
			printf("\r\nC:\\Admin> ");
			fflush(stdout);
		}

		IsCplt = false; /* 명령어 처리 완료 플래그 초기화 */
	}
}
