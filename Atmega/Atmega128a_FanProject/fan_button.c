#include "fan_config.h"
#include "fan_button.h"

// 💡 핵심: static을 붙여서 이 파일 안에서만 값을 기억하게 만듭니다. (main.c는 몰라도 됨)
static uint8_t prev_btn0 = 1; // 초기값 1 (풀업 상태)
static uint8_t prev_btn1 = 1; 

void button_process(void) {
    // 현재 버튼 상태 읽기
    uint8_t curr_btn0 = (PINA & (1 << PA0)) >> PA0;
    uint8_t curr_btn1 = (PINA & (1 << PA1)) >> PA1;

    // --- [물리 버튼 0 (풍속) 처리] ---
    if (curr_btn0 == 0 && prev_btn0 == 1) {
        _delay_ms(30); // 채터링 방지
        if (((PINA & (1 << PA0)) >> PA0) == 0) {
            speed_state++;
            if (speed_state > 3) speed_state = 0; 
            is_running = (speed_state == 0) ? 0 : 1;
        }
    }
    prev_btn0 = curr_btn0; // 과거 상태 업데이트

    // --- [물리 버튼 1 (회전) 처리] ---
    if (curr_btn1 == 0 && prev_btn1 == 1) {
        _delay_ms(30);
        if (((PINA & (1 << PA1)) >> PA1)  == 0) {
            rotate_state ^= 1; 
        }
    }
    prev_btn1 = curr_btn1; // 과거 상태 업데이트
}
