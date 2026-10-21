# STM32F411RE Peripheral Learning

STM32F411RE에서 STM32CubeMX와 HAL 드라이버를 사용하여 주변장치를 제어한 학습 기록입니다.

ATmega128A에서 레지스터를 직접 설정하며 익힌 주변장치 동작 원리를 바탕으로, STM32에서는 CubeMX가 생성한 초기화 코드와 HAL API가 어떤 레지스터 동작을 추상화하는지 함께 확인합니다. 수업 당시의 코드 흐름은 보존하고, 오류 정정이나 구조 개선이 필요한 경우에는 별도 버전으로 구분합니다.

## 정리 원칙

- 각 학습 버전의 진입점은 코드 조각이 아닌 STM32CubeMX/CubeIDE 생성 형식을 유지한 전체 `main.c`로 보존합니다.
- 사용자 Include, 자료형, Define·Macro, 전역 변수 및 함수 원형은 대응하는 `USER CODE` 영역에 배치합니다.
- `main()`의 로컬 변수는 `USER CODE BEGIN 1`, 주변장치 시작·초기 호출은 `2`, Main Loop 로직은 `3`, 사용자 함수·HAL Callback은 `4`에 배치합니다.
- 수업 원본과 개인 작성 코드는 가능한 한 그대로 보존합니다.
- 원본이 확인되지 않은 코드는 `Reconstructed`로 명확하게 표시합니다.
- 오류가 포함된 코드도 학습 과정의 근거가 되는 경우 원인과 함께 보존합니다.
- 개선 코드는 원본을 덮어쓰지 않고 별도 버전으로 추가합니다.
- CubeMX 설정, HAL API, 관련 레지스터의 관계를 함께 기록합니다.
- 빌드 및 실물 보드 검증 여부를 구분하여 표시합니다.

## 학습 목차

1. `01_GPIO`
   - LED, Tact Switch, Character LCD, SG-207 Photo Interrupter 및 GPIO EXTI
2. `02_UART`
   - Polling, Interrupt 및 DMA 기반 송수신 처리 방식 비교

이후 I2C, Timer 및 ADC 학습을 Peripheral 기준으로 추가합니다.

