#ifndef INC_PHOTO_H_
#define INC_PHOTO_H_

#include "main.h"
#include <stdbool.h>

/*
	엘리베이터가 맨 위층(천장)에 도달하여 상단 포토 센서가 가려졌는지 확인하는 함수
	반환값: true (센서가 가려짐, 즉시 상승 중지 필요), false (센서가 뚫려 있음)
 */
bool Photo_IsTopBlocked(void);

/*
	엘리베이터가 맨 아래층(바닥)에 도달하여 하단 포토 센서가 가려졌는지 확인하는 함수
	반환값: true (센서가 가려짐, 즉시 하강 중지 필요), false (센서가 뚫려 있음)
 */
bool Photo_IsBottomBlocked(void);

#endif /* INC_PHOTO_H_ */
