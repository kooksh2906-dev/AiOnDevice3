#include <door.h>

/*
	도어 제어 구조체를 초기 상태로 세팅하는 함수
	모터 속도(interval)와 문이 완전히 개방되기 위한 목표 스텝(target)을 설정
	시스템 시작 시 모터가 무단으로 도는 것을 막기 위해 전력을 차단
*/
void door_init(DOOR_CONTROL *door, uint32_t interval, uint32_t target)
{
    door->interval = interval;
    door->lastTick = 0;
    door->mode = DOOR_IDLE;
    door->currentStep = 0;
    door->targetStep = target;
    door->stepIdx = 0;

    /* 처음 시작할 때 모터 핀을 모두 Low로 초기화하여 과열 방지 */
    stopMotor1();
}


/*
	1-2상 여자 방식 모터 구동 패턴 (8단계)
	스텝 모터를 부드럽고 정밀하게 회전시키기 위한 8개의 핀 출력 상태 배열
	1은 전원 인가(HIGH), 0은 전원 차단(LOW)을 의미
*/
static const uint8_t HALF_STEP_SEQ[8][4] =
{
        {1, 0, 0, 0},
        {1, 1, 0, 0},
        {0, 1, 0, 0},
        {0, 1, 1, 0},
        {0, 0, 1, 0},
        {0, 0, 1, 1},
        {0, 0, 0, 1},
        {1, 0, 0, 1},
};

/*
	도어 모터로 들어가는 모든 전력을 차단하는 함수
	문이 완전히 열리거나 닫힌 후 대기 상태일 때, 모터에 불필요한 전류가 계속 흘러 뜨겁게 과열되는 현상을 방지
*/
void stopMotor1(void)
{
    HAL_GPIO_WritePin(IN1_DOOR_PORT, IN1_DOOR_PIN, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(IN2_DOOR_PORT, IN2_DOOR_PIN, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(IN3_DOOR_PORT, IN3_DOOR_PIN, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(IN4_DOOR_PORT, IN4_DOOR_PIN, GPIO_PIN_RESET);
}

/*
	전달받은 인덱스(step)에 해당하는 배열 패턴을 모터 제어 핀에 실제로 출력하는 함수
*/
void stepMotor1(uint8_t step)
{
    HAL_GPIO_WritePin(IN1_DOOR_PORT, IN1_DOOR_PIN, HALF_STEP_SEQ[step][0]);     // 1행의 1열
    HAL_GPIO_WritePin(IN2_DOOR_PORT, IN2_DOOR_PIN, HALF_STEP_SEQ[step][1]);     // 1행의 2열
    HAL_GPIO_WritePin(IN3_DOOR_PORT, IN3_DOOR_PIN, HALF_STEP_SEQ[step][2]);     // 1행의 3열
    HAL_GPIO_WritePin(IN4_DOOR_PORT, IN4_DOOR_PIN, HALF_STEP_SEQ[step][3]);     // 1행의 4열
}

/*
	지정된 스텝 수만큼 모터를 연속으로 회전시키는 블로킹(Blocking) 방식 함수
*/
void rotateSteps(uint16_t steps, uint8_t direction)
{
    for(uint16_t i = 0; i < steps; i++)
    {
        uint8_t step;

        /* 시계 방향 또는 반시계 방향에 따라 배열을 읽는 순서를 결정 */
        if(direction == DIR_CW)
        {
            step = i % 8;
        }
        else
        {
            step = 7 - (i % 8); /* 반시계 방향: 인덱스를 거꾸로 읽음 */
        }
        stepMotor1(step); /* 결정된 패턴을 모터에 출력 */

        HAL_Delay(1);   // 각 스탭 간의 지연시간
    }
}

void rotateDegrees(uint16_t degrees, uint8_t direction)
{
        // 각도계산 // 내 각도에 해당하는 스탭수 곱해서 360도로 나눔 형변환(16비트)해서 스탭수만큼 맞춰줌
       uint16_t steps = (uint16_t)((uint32_t) (degrees * STEPS_PER_REVOLATION) / 360);
       rotateSteps(steps, direction);

}

/*
	원하는 각도(도 단위)를 스텝 수로 변환하여 회전시키는 블로킹 함수
*/
void process_door_input(DOOR_CONTROL *door) {

	/* PC6 핀 스위치가 눌렸고, 문이 아직 다 열리지 않은 상태라면 열림 모드로 전환 */
    if (HAL_GPIO_ReadPin(GPIOC, GPIO_PIN_6) == GPIO_PIN_RESET) {
        if (door->currentStep < door->targetStep) {
            door->mode = DOOR_OPENING;
        }
    }

    /* PC8 핀 스위치가 눌렸고, 문이 조금이라도 열려있는 상태라면 닫힘 모드로 전환 */
    if (HAL_GPIO_ReadPin(GPIOC, GPIO_PIN_8) == GPIO_PIN_RESET) {
        if (door->currentStep > 0) {
            door->mode = DOOR_CLOSING;
        }
    }
}

/*
	시스템 메인 루프에서 지속적으로 호출되어 문을 비동기로 부드럽게 움직이는 핵심 제어 로직
	HAL_Delay를 쓰지 않고 Tick(시간)을 비교하여, 정해진 시간(interval)마다 1스텝씩 전진
*/
void updateDoor(DOOR_CONTROL *door)
{
    uint32_t DoorCurrentTick = HAL_GetTick();

    /* 1. 현재 문이 정지(대기) 상태라면 연산하지 않고 바로 빠져나감 */
    if (door->mode == DOOR_IDLE) return;

    /* 2. 설정한 interval의 시간이 지났는지 확인 */
    if (DoorCurrentTick - door->lastTick >= door->interval)
    {
        door->lastTick = DoorCurrentTick;

        if (door->mode == DOOR_OPENING)
        {
        		/* 반시계 방향 회전 (배열 인덱스를 빼는 로직) */
            door->stepIdx = (door->stepIdx == 0) ? 7 : door->stepIdx - 1;
            door->currentStep++;

            /* 문이 목표 각도(targetStep)만큼 다 열렸다면 동작을 멈추고 전류를 차단 */
            if (door->currentStep >= door->targetStep)
            {
                door->mode = DOOR_IDLE;
                stopMotor1();

            }
        }
        else if (door->mode == DOOR_CLOSING)
        {
        		/* 시계 방향 회전 (배열 인덱스를 더하는 로직) */
        	door->stepIdx = (door->stepIdx + 1) % 8;

        		/* 문이 끝까지 다 닫혔다면 (currentStep이 0이 됨) 동작을 멈추고 전류를 차단 */
            if (door->currentStep > 0) door->currentStep--;
            if (door->currentStep == 0)
                {
                    door->mode = DOOR_IDLE;
                    stopMotor1();
                }
        }

        	/* 3. 위에서 계산된 방향과 인덱스에 맞춰 실제 모터 핀에 신호를 1번 출력 */
        stepMotor1(door->stepIdx);
    }
}
