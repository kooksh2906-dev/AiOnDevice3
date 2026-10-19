#include "ultrasonic.h"

float Get_Center_Distance(void) {
    // 하드웨어 타이머 인풋 캡처 및 계산된 전방 거리 반환
    return dist_center_val; // 내부 구현에 맞춰 연동
}

float Get_Left_Distance(void) {
    return dist_left_val;
}

float Get_Right_Distance(void) {
    return dist_right_val;
}
