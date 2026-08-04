#ifndef INC_PASSWORD_H_
#define INC_PASSWORD_H_

#include "main.h"

/*
	시스템 시작 시 한 번 호출되는 초기화 함수
	내부적으로 LCD 모듈을 초기화하고, 화면에 "Press Password" 같은 첫 시작 안내 문구를 띄워주는 역할
*/
void Password_Init(void);

/*
메인 루프(while) 안에서 지속적으로 호출되어야 하는 업데이트 함수
사용자가 키패드를 누르는지 실시간으로 감지(스캔)하고, 입력된 글자를 조립하여 정답과 비교하는 모든 핵심 로직이 들어옴
*/
void Password_Update(void);

#endif /* INC_PASSWORD_H_ */
