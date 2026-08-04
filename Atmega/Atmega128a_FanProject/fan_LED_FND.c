#include "fan_config.h"
#include "fan_LED_FND.h"

// FND 숫자 패턴 (이 파일 내부에서만 사용하므로 static)
static uint8_t fndNumber[] = {0x3F, 0x06, 0x5B, 0x4F};

volatile uint8_t brightness[8] = {0};

void visual_init(void) {
    DDRC = 0xFF; // FND 포트 출력 설정
    DDRD = 0xFF; // LED 바 포트 출력 설정

    // Timer0 (LED 소프트웨어 PWM 제어용, 분주비 8)
    TCCR0 |= (1 << CS01); 
    TIMSK |= (1 << TOIE0); 
}

void display_speed(uint8_t state) { //
    if (state > 3) state = 0; // 예외 처리
    PORTC = fndNumber[state]; // FND에 패턴 출력
}

void update_led_sweep(uint16_t servo_pos) {
    // 250~500 사이를 8개로 나눈 좌표
    int16_t led_pos[8] = {250, 286, 321, 357, 393, 429, 464, 500};
    int16_t spread = 50; // 번짐 범위를 50으로 조정 (취향에 따라 조절 가능)

    if (rotate_state == 1) { 
        for(int i = 0; i < 8; i++) {
            // 현재 서보 위치와 각 LED 좌표 간의 거리 계산
            int16_t diff = abs((int16_t)servo_pos - led_pos[i]); 
            
            if (diff < spread) {
                // 거리에 따른 밝기 계산 (0~100)
                brightness[i] = 100 - (diff * 100 / spread);
            } else {
                brightness[i] = 0;
            }
        }
    } else { 
        for(int i = 0; i < 8; i++) brightness[i] = 0;
    }
}



// Timer0 
인터럽트: LED 8개의 밝기를 소프트웨어 PWM으로 개별 제어
ISR(TIMER0_OVF_vect) 
{
    static uint8_t soft_pwm_cnt = 0;
    uint8_t out_portd = 0;

    soft_pwm_cnt++;
    if (soft_pwm_cnt >= 100) soft_pwm_cnt = 0; 
    
    // 8개의 LED(0~7)를 각 포트핀(PD0~PD7)에 1:1 매칭
    if (brightness[0] > soft_pwm_cnt) out_portd |= (1 << PD0);
    if (brightness[1] > soft_pwm_cnt) out_portd |= (1 << PD1);
    if (brightness[2] > soft_pwm_cnt) out_portd |= (1 << PD2);
    if (brightness[3] > soft_pwm_cnt) out_portd |= (1 << PD3);
    if (brightness[4] > soft_pwm_cnt) out_portd |= (1 << PD4);
    if (brightness[5] > soft_pwm_cnt) out_portd |= (1 << PD5);
    if (brightness[6] > soft_pwm_cnt) out_portd |= (1 << PD6);
    if (brightness[7] > soft_pwm_cnt) out_portd |= (1 << PD7);

    PORTD = out_portd; 
}
