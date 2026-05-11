#include "fan_config.h"

// [시스템 3대 핵심 상태]
volatile uint8_t is_running = 1;         
volatile uint8_t speed_state = 0;   
volatile uint8_t rotate_state = 0;  

int main(void)
{
    // 1. 초기화 구역
    register_init(); 
    comm_init();   
    motor_init();  
    visual_init(); 

    sei(); // Set Enable Global Interrupt of Atmega128a
    uart0_print("\r\n=== Fan Project Boot: Ultimate Diet ===\r\n");


    while(1)
    {
        // --- [STEP 1] 입력 감시 ---
        comm_process();    
        button_process();  

        // --- [STEP 2] 모터 제어 ---
        set_fan_speed(speed_state); 
        
        // --- [STEP 3] 시각 출력 (데이터 다이렉트 패스!) ---
        display_speed(speed_state);              
        update_led_sweep(update_motor_rotation()); 

        _delay_ms(15); 
    }
    return 0;
}
