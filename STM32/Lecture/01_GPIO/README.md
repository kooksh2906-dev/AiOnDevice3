# 01. GPIO

STM32F411RE의 GPIO를 직접 Register, HAL 기반 출력·입력 및 외부 인터럽트 방식으로 사용하는 학습 기록입니다.

직접 Register LED 실습에서는 CubeMX와 HAL 없이 RCC, FLASH, GPIOA와 SysTick Register를 설정하여 PA5 온보드 LED를 점멸합니다. 이후 CubeMX 생성 코드와 `HAL_GPIO_WritePin()`, `HAL_GPIO_TogglePin()`을 사용하는 LED 제어부터 Tact Switch, Character LCD, SG-207 포토인터럽터 및 EXTI 실습까지 학습 범위를 확장합니다.

## 자료 보관 기준

- GitHub에는 학습 코드와 설정 문서를 저장합니다.
- CubeMX 설정 및 원본 코드 캡처처럼 학습 과정을 보여 주는 이미지는 해당 Notion 학습 항목에 보존합니다.
- 직접 Register 실습의 원본은 수정하지 않고, 설정 보완이 필요한 코드는 별도 교정본으로 구분합니다.

## 학습 항목

0. `00_Direct_Register_LED`
   - HSE 8 MHz와 PLL을 이용한 SYSCLK 100 MHz 직접 설정
   - RCC·FLASH·GPIOA Memory-Mapped Register 기반 PA5 LD2 제어
   - `for` Busy-wait와 SysTick COUNTFLAG Polling 지연 비교
   - 원본 2개 버전 보존과 HSE Bypass·SWS 확인 교정본
1. `01_LED`
   - `HAL_Delay()` 기반 Blocking 제어
   - `HAL_GetTick()` 기반 Non-Blocking 제어
   - 다중 LED 상태 구조체와 모듈 분리
2. `02_Tact_Switch`
   - PC13 User Button의 Active-High 입력 판독
   - Level Polling과 Press Edge의 차이
   - Blocking 및 Non-Blocking Debounce 비교
3. `03_Character_LCD`
   - 8-bit 및 4-bit GPIO 병렬 Interface 비교
   - Command/Data 전송, Enable Pulse 및 DDRAM Cursor Address
   - 4-bit 초기화 순서와 Nibble 전달
4. `04_SG207_Photo_Interrupter`
   - SG-207의 적외선 LED와 포토트랜지스터 동작 원리
   - PC4 GPIO Input과 Active-Low Collector 출력
   - `HAL_GPIO_ReadPin()` 기반 200 ms Polling 및 Debugger 관찰
5. `05_GPIO_EXTI`
   - PC13 Rising Edge와 EXTI15_10 Interrupt 처리
   - 원본 Callback 보존 및 GPIO Pin 필터링
   - ISR 최소화와 Main Loop 지연 처리 방식
