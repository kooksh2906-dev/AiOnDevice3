# 05. HC-SR04 Ultrasonic Distance Measurement

STM32F411RE에서 GPIO로 HC-SR04의 Trigger Pulse를 만들고, TIM3 Channel 1 Input Capture로 Echo High Pulse의 폭을 측정하여 거리를 계산한 실습입니다. TIM11은 1 MHz Free-running Counter로 설정하여 10 us Trigger Pulse를 생성했고, 측정값은 USART2 `printf()` Retargeting으로 Tera Term에 출력했습니다.

수업 메일의 CubeMX 설정, 소스 화면 및 실제 Tera Term 결과를 기준으로 전체 CubeIDE 형식 `main.c`와 `delay.c/.h`를 복원했습니다. RM0383의 Timer Input Capture Register 흐름, UM1725의 HAL Input Capture API 및 HC-SR04 Module Guide의 Timing 조건을 코드와 연결했습니다.

## 1. 실제 실습 구성

| 구분 | 설정·연결 | 역할 |
|---|---|---|
| Board | NUCLEO-F411RE | STM32F411RE 실행 보드 |
| HC-SR04 Trigger | PA5, GPIO Output | 10 us High Pulse 출력 |
| HC-SR04 Echo | PA6, AF2 TIM3_CH1 | Echo High Pulse의 Rising/Falling Edge 캡처 |
| TIM3 | PSC 99, ARR 65535, CH1 Direct Input | 1 us 단위 Echo Pulse Width 측정 |
| TIM11 | PSC 99, ARR 65535 | `delay_us()`용 1 us Time Base |
| USART2 | PA2 TX, PA3 RX | ST-LINK Virtual COM Port와 Tera Term 출력 |

수업 결과 화면에는 `IC_Value1`, `IC_Value2`와 `distance`가 연속 출력되어 있으며 약 5~22 cm의 거리 변화가 확인됩니다. 예를 들어 `46658 us -> 47227 us`는 569 us의 Echo Pulse이며, 정수식 `569 / 58`로 9 cm가 출력됩니다.

## 2. HC-SR04 Timing과 거리 계산

HC-SR04는 Trigger 입력에 10 us 이상의 High Pulse가 들어오면 40 kHz 초음파 8 Cycle을 송신하고, 반사파를 기다리는 동안 Echo를 High로 유지합니다. 따라서 Echo High 시간은 초음파가 물체까지 갔다가 돌아오는 왕복 시간입니다.

```text
distance = sound_speed x echo_time / 2

20 °C 부근의 음속 약 0.0343 cm/us를 사용하면
distance [cm] = echo_time [us] x 0.0343 / 2
              ~= echo_time [us] / 58
```

공유된 Module Guide는 2~400 cm, 약 +/-3 mm를 명시하고 있으며, 다음 Trigger까지 60 ms보다 긴 측정 주기를 권장합니다. 수업 원본의 500 ms와 개선본의 100 ms는 모두 이 간격보다 깁니다.

## 3. 1 us Timer Time Base

수업 Clock Tree에서 TIM3과 TIM11의 입력 Clock은 모두 100 MHz입니다. APB 경로는 다르지만 결과적인 Timer Clock은 같습니다.

```text
f_TIM = 100,000,000 Hz
PSC   = 99

f_CNT = f_TIM / (PSC + 1)
      = 100,000,000 / 100
      = 1,000,000 Hz

1 Count = 1 us
```

ARR 65535인 16-bit Up-counter의 전체 주기는 65,536 us입니다. HC-SR04의 일반적인 최대 Echo 대기 시간 약 38 ms보다 길어 한 번의 정상 측정에서 Counter가 두 번 이상 Wrap될 가능성을 피합니다.

TIM11은 `delay_us()`에서 Counter를 0으로 만든 뒤 지정한 Count까지 기다립니다. TIM3은 Free-running 상태에서 Echo Rising/Falling Edge의 CCR1 값을 각각 저장하고 두 Capture 값의 차이로 Pulse Width를 계산합니다.

## 4. Input Capture 실행 흐름

1. PA5를 High로 만들고 TIM11 기반 `delay_us(10)` 후 Low로 내려 Trigger Pulse를 만듭니다.
2. Echo가 Rising Edge가 되면 TIM3 CNT가 CCR1에 Latch되고 CC1 Interrupt가 발생합니다.
3. `HAL_TIM_IC_CaptureCallback()`이 첫 Capture 값을 저장하고 CH1 Polarity를 Falling Edge로 전환합니다.
4. Echo가 Falling Edge가 되면 두 번째 CCR1 값을 읽습니다.
5. 두 Capture의 차이를 Echo High 시간으로 계산하고 `/ 58`로 cm 거리를 구합니다.
6. Polarity를 다시 Rising Edge로 바꾸고 다음 측정을 준비합니다.

`HAL_TIM_ReadCapturedValue()`는 선택 Channel의 CCRx 값을 읽습니다. `__HAL_TIM_SET_CAPTUREPOLARITY()`는 CCER의 Polarity Bit를 바꾸며, `__HAL_TIM_ENABLE_IT()`와 `__HAL_TIM_DISABLE_IT()`는 DIER의 CC1 Interrupt Enable을 제어합니다.

## 5. 버전 구성

| 버전 | 성격 | 내용 |
|---|---|---|
| `VER1_Reconstructed_Lecture_Single_Sensor` | 수업 화면 기반 복원본 | PA5 Trigger, PA6/TIM3_CH1 Echo, TIM11 `delay_us()`, Rising/Falling 전환, `/58` 거리 계산, 500 ms 주기 및 USART2 출력 흐름을 보존했습니다. |
| `VER2_Improved_Timeout_Overflow_Safe` | 별도 개선본 | 원본의 HW 설정을 유지하면서 Timer/Channel 식별, `volatile`, 16-bit Wrap의 `ARR+1` 보정, 40 ms Timeout, 100 ms 측정 주기, 넓은 거리 자료형 및 ISR/Foreground Snapshot을 추가했습니다. |

두 버전 모두 전체 STM32CubeMX/CubeIDE 형식 `main.c`로 정리했습니다. 사용자 함수 원형은 `USER CODE BEGIN PFP`, Timer 시작은 `USER CODE BEGIN 2`, Main Loop 로직은 `USER CODE BEGIN 3`, Trigger 함수·Input Capture Callback·`printf()` Retargeting은 `USER CODE BEGIN 4`에 배치했습니다.

## 6. 수업 원본에서 확인한 보완 지점

### 6.1 Counter Wrap 계산

수업 코드는 Wrap이 발생하면 다음 식을 사용합니다.

```c
echoTime = (0xFFFFU - IC_Value1) + IC_Value2;
```

16-bit Counter는 `0..65535`의 65,536 Count를 가지므로 정확한 Modular Difference에는 `ARR+1`이 필요합니다. 개선본은 다음처럼 계산합니다.

```c
counterPeriod = __HAL_TIM_GET_AUTORELOAD(htim) + 1U;
pulseWidth = (counterPeriod - risingCapture) + fallingCapture;
```

원본과의 차이는 Wrap이 발생한 측정에서 1 us이며, 학습 기록을 보존하기 위해 원본 식은 복원본에 그대로 남겼습니다.

### 6.2 Echo Timeout

원본은 Echo Falling Edge가 오지 않아도 500 ms마다 이전 값을 출력할 수 있고, Capture 상태가 Falling Edge 대기에 머물 수 있습니다. 개선본은 Trigger 후 40 ms 안에 측정이 끝나지 않으면 CC1 Interrupt와 Capture 상태를 초기화하고 `out of range or echo timeout`을 출력합니다.

### 6.3 ISR 공유 데이터

원본의 Capture 값과 거리는 Interrupt Callback과 Main Loop가 함께 사용하지만 `volatile`이 아닙니다. 개선본은 공유 변수를 `volatile`로 선언하고, 출력 전에 짧은 Critical Section에서 Pulse Width·거리·Timeout 상태를 Snapshot으로 복사합니다. UART 출력은 ISR 밖에서 수행합니다.

### 6.4 자료형과 Callback 식별

- 원본 `uint8_t distance`는 255 cm까지만 표현할 수 있으므로 Guide의 400 cm 범위를 모두 담지 못합니다. 개선본은 `uint16_t`를 사용합니다.
- 원본 Callback은 Active Channel만 확인합니다. 개선본은 `htim->Instance == TIM3`와 `HAL_TIM_ACTIVE_CHANNEL_1`을 함께 검사합니다.
- 원본은 Capture가 끝날 때 Counter를 0으로 만듭니다. 개선본은 Free-running Counter를 유지하고 Modular Difference만 사용합니다.

## 7. CubeMX·HAL·Register 연결

| CubeMX/HAL | 주요 Register·Bit | 의미 |
|---|---|---|
| TIM3 Internal Clock | `RCC_APB1ENR.TIM3EN`, `CK_INT` | TIM3 Clock 공급과 내부 Clock 선택 |
| TIM11 Activated | `RCC_APB2ENR.TIM11EN` | TIM11 Clock 공급 |
| Prescaler 99 | `TIMx_PSC` | 100 MHz를 1 MHz Counter Clock으로 분주 |
| Period 65535 | `TIMx_ARR` | 16-bit Counter의 Top과 65.536 ms Wrap 주기 설정 |
| CH1 Direct Input | `TIM3_CCMR1.CC1S=01` | TI1을 IC1에 직접 연결 |
| Rising/Falling Polarity | `TIM3_CCER.CC1P`, `CC1NP` | 캡처할 Edge 선택 |
| Input Prescaler 1 | `TIM3_CCMR1.IC1PSC=00` | 모든 유효 Edge를 Capture |
| Input Filter 0 | `TIM3_CCMR1.IC1F=0000` | Digital Filter 없이 입력 샘플링 |
| CC1 Interrupt | `TIM3_DIER.CC1IE` | Capture/Compare 1 Interrupt 허용 |
| Capture Flag | `TIM3_SR.CC1IF` | CCR1에 Capture가 발생했음을 표시 |
| Captured Count | `TIM3_CCR1` | Edge 시점의 CNT 값을 Latch |
| `HAL_TIM_IC_Start[_IT]()` | `CC1E`, `CEN`, 선택 시 `CC1IE` | Input Capture Channel과 Counter 시작 |
| `HAL_TIM_ReadCapturedValue()` | `CCR1` Read | 저장된 Edge 시점 읽기 |

## 8. 전기적 연결 확인

공유된 `HC-SR04-Ultrasonic.pdf`는 3.3~5 V에서 동작하는 2세대 Module을 설명합니다. 다만 `HC-SR04` 이름으로 유통되는 Module은 Version과 Echo 출력 전압 조건이 다를 수 있으므로, 실제 Module의 공급사 문서와 Echo High Level을 확인한 뒤 STM32 GPIO 허용 전압에 맞게 직접 연결 또는 Level Shifting/분압을 결정해야 합니다. 특정 Guide의 3.3 V 호환 조건을 모든 HC-SR04 호환품에 일반화하지 않습니다.

## 9. 핵심 학습 포인트

- Output GPIO로 정해진 Trigger Pulse를 만들고 Input Capture로 외부 Pulse Width를 Hardware 기준으로 측정할 수 있습니다.
- PSC를 설정할 때 APB Clock Tree에서 실제 `TIMxCLK`를 먼저 구하고 1 Count의 시간을 계산해야 합니다.
- Input Capture는 Edge 순간의 CNT를 CCR에 Latch하므로 Main Loop Polling보다 정확한 Pulse Timing에 유리합니다.
- 하나의 Channel에서 Rising/Falling Edge를 번갈아 선택하여 Pulse의 시작과 끝을 측정할 수 있습니다.
- 16-bit Counter의 Wrap 계산에는 `ARR+1`을 포함한 Modular Difference가 필요합니다.
- 센서의 정상 범위뿐 아니라 Echo 미수신, 범위 초과, stale data 및 상태 복구를 함께 설계해야 합니다.
- ISR에서는 Capture와 상태 갱신만 짧게 수행하고 문자열 출력은 Main Context에서 처리합니다.
- HC-SR04의 `/58` 식은 왕복 시간과 음속을 반영한 근사식이며, 온도와 반사면 조건이 측정 오차에 영향을 줍니다.

## 10. 검증 범위

- 수업 메일의 CubeMX Pinout, TIM11/TIM3 설정, NVIC, `delay.c`, `main.c` 일부 화면과 Tera Term 결과를 서로 대조했습니다.
- HC-SR04 Module Guide의 10 us Trigger, 40 kHz 8 Cycle, `/58` 거리식 및 60 ms 이상 측정 간격을 반영했습니다.
- RM0383 Rev 3과 UM1725 Rev 8을 기준으로 TIM3 Input Capture, Interrupt, Polarity 전환 및 Capture Register 흐름을 정적 검토했습니다.
- GitHub에는 코드와 설정 문서만 보존하고, 실제 수업 화면과 실행 결과는 Notion에 배치합니다.
- 전체 `main.c`와 `delay.c`는 HAL Stub을 이용한 C 문법·경고 검사를 수행합니다.
- 원본 `.ioc`, 생성된 `tim.c/.h`, `gpio.c/.h`, `usart.c/.h`, Interrupt Handler 및 전체 CubeIDE Project는 현재 보관본에 포함되지 않았습니다.
- 이번 정리 과정에서 CubeIDE 재빌드와 실물 Board 재시험은 수행하지 않았습니다. Tera Term 출력은 수업 당시 저장한 실행 결과입니다.

## 참고 문서

- STMicroelectronics, *RM0383: STM32F411xC/E Reference Manual*, Rev 3
- STMicroelectronics, *UM1725: Description of STM32F4 HAL and Low-layer Drivers*, Rev 8
- HandsOn Technology, *HC-SR04 Ultrasonic Sensor Module User Guide*, V2.02
