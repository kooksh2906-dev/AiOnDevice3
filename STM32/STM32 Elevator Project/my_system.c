#include "my_system.h"

void SysInit(){

	DOOR_CONTROL elevator_door;

	Password_Init();
	door_init(&elevator_door, 2, 1024);

	while(!Photo_IsBottomBlocked()){

		if (HAL_GetTick() - last_motor_time >= 2){

			last_motor_time = HAL_GetTick();
			motor_step--;
			if (motor_step < 0){
				motor_step = 7;
			}
			stepMotor(motor_step);

		}

		if (HAL_GetTick() - last_led_time >= 100){

			last_led_time = HAL_GetTick();


			if (led_index == 0) led_index = 7;
			else led_index--;
			LED_Update(led_index);
		}
	}
}


void SysReset(){

    uint8_t DoorCloseFlag = 0;

    // 0. 문 제어 구조체 초기화 (쓰레기 값 방지)
    door_init(&elevator_door, 2, 1024);

    // 1. 일단 1층으로 내려오기
    while(!Photo_IsBottomBlocked()){
        if (HAL_GetTick() - last_motor_time >= 2){
            last_motor_time = HAL_GetTick();
            motor_step--;
            if (motor_step < 0){
                motor_step = 7;
            }
            stepMotor(motor_step);
        }
    }
    motorStop(); // 바닥에 완전히 도달했으므로 리프트 모터 정지 (안전을 위해 권장)

    // 2. 승강기 문 완전히 열어주기
    if (elevator_door.currentStep < elevator_door.targetStep) {
        elevator_door.mode = DOOR_OPENING;
    }

    // 문 열기 모드가 완료(DOOR_IDLE)될 때까지 반복해서 updateDoor 호출
    while(elevator_door.mode != DOOR_IDLE) {
        updateDoor(&elevator_door);
    }

    // 3. 문이 다 열린 시점부터 3초 동안 대기 (HAL_Delay 대체 블로킹)
    uint32_t wait_start_time = HAL_GetTick(); // 대기 시작 시간 기록
    while(HAL_GetTick() - wait_start_time < 3000) {
        // 3000ms(3초)가 지날 때까지 아무것도 하지 않고 이 루프에 갇혀서 대기합니다.
        // (필요하다면 이 내부에 비상 정지 버튼 폴링 코드를 넣을 수도 있습니다)
    }
    DoorCloseFlag = 1; // 3초가 안전하게 지나면 플래그 세팅

    // 4. 3초 후 승강기 문 완전히 닫아주기
    if(DoorCloseFlag == 1){
        if (elevator_door.currentStep > 0) {
            elevator_door.mode = DOOR_CLOSING;
        }

        // 문 닫힘 모드가 완료(DOOR_IDLE)될 때까지 반복해서 updateDoor 호출
        while(elevator_door.mode != DOOR_IDLE) {
            updateDoor(&elevator_door);
        }
        DoorCloseFlag = 0;
    }
}

void CheckDoor(){

    uint8_t DoorCloseFlag = 0;

    // 0. 문 제어 구조체 초기화 필수 (쓰레기 값 방지 및 목표 스텝/속도 설정)
    door_init(&elevator_door, 2, 1024);

    // 1. 승강기 문 열기 모드 설정
    if (elevator_door.currentStep < elevator_door.targetStep) {
        elevator_door.mode = DOOR_OPENING;
    }

    // 문이 완전히 열릴 때까지(DOOR_IDLE 상태가 될 때까지) 반복해서 updateDoor 호출
    while(elevator_door.mode != DOOR_IDLE) {
        updateDoor(&elevator_door);
    }

    // 2. 문이 다 열린 시점부터 1초(1000ms) 동안 대기 (HAL_Delay 대체 블로킹)
    uint32_t wait_start_time = HAL_GetTick(); // 대기 시작 시간 기록
    while(HAL_GetTick() - wait_start_time < 1000) {
        // 1초가 지날 때까지 아무것도 하지 않고 이 루프에서 대기합니다.
    }
    DoorCloseFlag = 1; // 1초 대기가 끝나면 플래그 세팅

    // 3. 1초 후 승강기 문 완전히 닫아주기
    if(DoorCloseFlag == 1){
        if (elevator_door.currentStep > 0) {
            elevator_door.mode = DOOR_CLOSING;
        }

        // 문이 완전히 닫힐 때까지 반복해서 updateDoor 호출
        while(elevator_door.mode != DOOR_IDLE) {
            updateDoor(&elevator_door);
        }
        DoorCloseFlag = 0;
    }
}

void CheckLift(){
    // 1. 천장에 도달할 때까지 위로 이동 (motor_step 증가 방향)
    while(!Photo_IsTopBlocked()){
        if (HAL_GetTick() - last_motor_time >= 2){
            last_motor_time = HAL_GetTick();
            motor_step++;
            if (motor_step > 7){
                motor_step = 0;
            }
            stepMotor(motor_step);
        }
    }

    // 천장에 도착했으므로 모터 정지
    motorStop();

    // 2. [수정] HAL_Delay(500) 대신 HAL_GetTick()을 이용한 0.5초 대기
    uint32_t delay_start_time = HAL_GetTick(); // 대기 시작 시점 기록
    while(HAL_GetTick() - delay_start_time < 500) {
        // 500ms 가 지날 때까지 아무것도 안 하고 이 루프에서 대기
        // 모터가 멈춘 상태에서 방향을 바꾸기 전 전압/관성을 안정화하는 시간입니다.
    }

    // 3. 바닥에 도달할 때까지 아래로 이동 (motor_step 감소 방향)
    // 플래그 체크 없이, 위 루프와 대기가 끝나면 바로 이어서 실행됩니다.
    while(!Photo_IsBottomBlocked()){
        if (HAL_GetTick() - last_motor_time >= 2){
            last_motor_time = HAL_GetTick();
            motor_step--;
            if (motor_step < 0){
                motor_step = 7;
            }
            stepMotor(motor_step);
        }
    }

    // 바닥에 도착했으므로 최종 정지
    motorStop();
}



