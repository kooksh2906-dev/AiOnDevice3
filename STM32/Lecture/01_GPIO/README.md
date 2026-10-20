# 01. GPIO

STM32F411RE의 GPIO를 출력, 입력 및 외부 인터럽트 방식으로 사용하는 학습 기록입니다.

GPIO 출력 실습에서는 CubeMX가 생성한 초기화 코드와 `HAL_GPIO_WritePin()`, `HAL_GPIO_TogglePin()`의 역할을 확인합니다. 이후 Tact Switch 입력, EXTI 및 Character LCD 제어로 학습 범위를 확장합니다.

## 학습 항목

1. `01_LED`
   - `HAL_Delay()` 기반 Blocking 제어
   - `HAL_GetTick()` 기반 Non-Blocking 제어
   - 다중 LED 상태 구조체와 모듈 분리
2. `02_Tact_Switch`
   - PC13 Tact Switch의 Active-Low 입력 판독
   - Level Polling과 Press Edge의 차이
   - Blocking 및 Non-Blocking Debounce 비교
3. `03_GPIO_EXTI`
   - PC13 Rising Edge와 EXTI15_10 Interrupt 처리
   - 원본 Callback 보존 및 GPIO Pin 필터링
   - ISR 최소화와 Main Loop 지연 처리 방식

