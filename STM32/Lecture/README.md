# STM32F411RE Peripheral Learning

STM32F411RE에서 STM32CubeMX와 HAL 드라이버를 사용하여 주변장치를 제어하고, 학습 말미에는 HAL 없이 Memory-Mapped Register에 직접 접근하여 Clock과 GPIO를 구성한 기록입니다.

ATmega128A에서 레지스터를 직접 설정하며 익힌 주변장치 동작 원리를 바탕으로, STM32에서는 CubeMX가 생성한 초기화 코드와 HAL API가 어떤 레지스터 동작을 추상화하는지 확인했습니다. 마지막 직접 레지스터 LED 실습에서는 데이터시트와 레퍼런스 매뉴얼만으로 Clock Tree와 GPIO를 설정하며 저수준 제어와 HAL 추상화의 차이를 다시 연결했습니다. 수업 당시의 코드 흐름은 보존하고, 오류 정정이나 구조 개선이 필요한 경우에는 별도 버전으로 구분합니다.

## 정리 원칙

- CubeMX 기반 학습 버전의 진입점은 코드 조각이 아닌 STM32CubeMX/CubeIDE 생성 형식을 유지한 전체 `main.c`로 보존합니다.
- 사용자 Include, 자료형, Define·Macro, 전역 변수 및 함수 원형은 대응하는 `USER CODE` 영역에 배치합니다.
- `main()`의 로컬 변수는 `USER CODE BEGIN 1`, 주변장치 시작·초기 호출은 `2`, Main Loop 로직은 `3`, 사용자 함수·HAL Callback은 `4`에 배치합니다.
- CubeMX 없이 수행한 직접 레지스터 실습은 당시의 독립형 `main.c` 형식을 그대로 보존합니다.
- 수업 원본과 개인 작성 코드는 가능한 한 그대로 보존합니다.
- 원본이 확인되지 않은 코드는 `Reconstructed`로 명확하게 표시합니다.
- 오류가 포함된 코드도 학습 과정의 근거가 되는 경우 원인과 함께 보존합니다.
- 개선 코드는 원본을 덮어쓰지 않고 별도 버전으로 추가합니다.
- CubeMX 설정, HAL API 또는 직접 제어한 Register의 관계를 함께 기록합니다.
- 빌드 및 실물 보드 검증 여부를 구분하여 표시합니다.

## 학습 목차

1. `01_GPIO`
   - 직접 Register 기반 PA5 LED 제어, HAL LED, Tact Switch, Character LCD, SG-207 Photo Interrupter 및 GPIO EXTI
2. `02_UART`
   - Polling, Interrupt 및 DMA 기반 송수신 처리 방식 비교
3. `03_I2C`
   - I2C Protocol, PCF8574 기반 Character LCD 및 I2C·SPI·Ethernet 비교
4. `04_TIMER`
   - TIM11 Base Timer Update Interrupt와 TIM3 PWM LED Duty 제어
5. `05_HC_SR04`
   - GPIO Trigger, TIM3 Input Capture 및 TIM11 1 us Time Base를 이용한 초음파 거리 측정
6. `06_MG996R`
   - TIM3 CH1 50 Hz PWM과 USART2 Interrupt 명령을 이용한 Servo Motor 위치 제어
7. `07_ULN2003`
   - 28BYJ-48의 1상·2상·1-2상 여자와 GPIO Polling·TIM10 Interrupt 기반 Stepper Motor 제어
8. `08_Passive_Piezo_Buzzer`
   - PB6/TIM4 CH1 PWM의 주파수·Duty 제어를 이용한 수동 피에조 부저 음계와 멜로디 재생
9. `09_DHT11`
   - PC4 양방향 GPIO, TIM11 1 us Counter와 40 bit Checksum 기반 온·습도 측정
10. `10_ADC_Joystick`
   - SZH-EK056의 ADC Polling·Interrupt와 2채널 Scan/Circular DMA 기반 X/Y 좌표 취득
11. `11_FreeRTOS`
   - 동일 우선순위 태스크의 공유변수 접근을 보호 없음·Mutex·Semaphore 방식으로 비교하고 임계영역 범위를 개선

현재 보관된 STM32 학습 목록은 직접 레지스터 LED 제어, ADC Joystick 및 FreeRTOS 공유변수 동기화까지 정리했습니다. 원본 `.ioc`, 생성 Driver와 전체 CubeIDE Project가 추가로 확보되면 각 항목의 재현 자료를 보완합니다.
