#include "fan_config.h"

// 풍속에 따른 PWM 값 매핑 테이블 (이사 옴)
static uint16_t fanSpeedTable[] = {0, 2500, 4000, 4999};

// 서보 모터 내부 상태 관리 (함수 내부에서만 사용)
static uint16_t local_servo_pos = 375; 
static int8_t local_servo_dir = 1;

void motor_init(void) {
    // 1. PB5, PB6 출력 설정
    DDRB |= (1 << PB5) | (1 << PB6);

    // 2. Timer1 설정 (Fast PWM, Mode 14)
    TCCR1A |= (1 << COM1A1) | (1 << COM1B1) | (1 << WGM11);
    TCCR1B |= (1 << WGM13) | (1 << WGM12) | (1 << CS11) | (1 << CS10); // 64분주
    ICR1 = 4999; // 50Hz
    
    OCR1A = 375; // 초기 서보 위치 (중앙)
    OCR1B = 0;   // 초기 모터 정지
   // volatile uint16_t current_servo_pos = 375;
}

// [풍속 제어 함수]
void set_fan_speed(uint8_t state) {
    if (state > 3) state = 0;
    
    OCR1B = fanSpeedTable[state];

    // 요구사항: 정지(0단) 상태가 되면 풍향 모터도 정지 및 중앙 정렬
    if (state == 0) {
        rotate_state = 0;     // 회전 상태 끔
        local_servo_pos = 375; // 내부 위치 변수 초기화
        OCR1A = 375;          // 하드웨어 중앙 정렬
    }
}

// [풍향 회전 업데이트 함수]
uint16_t update_motor_rotation(void) {
    if (rotate_state == 1) {
        local_servo_pos += local_servo_dir;
        
        if (local_servo_pos >= 500) local_servo_dir = -1;      
        else if (local_servo_pos <= 250) local_servo_dir = 1;  
        
        OCR1A = local_servo_pos; 
    }
    // 현재 서보 위치를 반환 (LED Bar 업데이트용)
    return local_servo_pos;
}
