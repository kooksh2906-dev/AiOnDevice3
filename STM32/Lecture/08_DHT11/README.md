# 08. DHT11 Temperature and Humidity Sensor

STM32F411RE가 DHT11의 전용 Single-bus 신호를 직접 생성·측정하여 온도와 상대습도를 읽은 학습 기록입니다. PC4 한 선을 출력과 입력으로 전환하고, TIM11의 1 us Counter로 응답 Pulse와 40 bit Data의 High 시간을 판별했습니다.

DHT11의 통신 방식은 한 Data 선을 사용하는 제조사 전용 방식이며, Dallas/Maxim의 표준 1-Wire Protocol과 동일한 Protocol로 보지 않습니다.

## 1. 실제 실습 구성

| 구분 | 설정·연결 | 역할 |
|---|---|---|
| Board | NUCLEO-F411RE | DHT11 제어와 UART 출력 |
| DHT11 DATA | PC4 | Start 신호 출력 후 응답·Data 입력 |
| Timer | TIM11, 1 MHz | 1 us 단위 Delay와 Pulse 폭 측정 |
| USART2 | PA2/PA3, ST-LINK VCP | `printf()` 온·습도와 오류 출력 |
| Pull-up | 수업 자료 기준 5 kΩ | DATA Idle High와 Bus Release 상태 유지 |

DHT11 Pin은 1번 VDD, 2번 DATA, 3번 NC, 4번 GND입니다. Bare Sensor를 사용할 때 DATA와 VDD 사이에 Pull-up 저항이 필요하며, 사용하는 Breakout Board에 저항이 내장되어 있는지 먼저 확인합니다. VDD-GND 사이에는 전원 안정화를 위한 100 nF Bypass Capacitor를 가까이 배치할 수 있습니다.

## 2. Sensor 사양과 Sampling 조건

| 항목 | DHT11 자료 기준 |
|---|---|
| 전원 | 3.0~5.5 V, Typical 5 V |
| 습도 측정 범위 | 20~90 %RH |
| 온도 측정 범위 | 0~50 °C |
| 습도 정확도 | 최대 ±5 %RH |
| 온도 정확도 | 최대 ±2 °C |
| 해상도 | 습도 1 %RH, 온도 1 °C |
| 최소 Sampling 간격 | 1 s 이상 |
| 통신 시간 | 약 4 ms |

전원 인가 후 Sensor가 안정화될 때까지 최소 1초 동안 명령을 보내지 않아야 합니다. 수업 코드는 측정 후 `HAL_Delay(2000)`을 사용했고, 개선본은 전원 인가 후 첫 측정도 2초 뒤에 실행하면서 `HAL_GetTick()`으로 2초 주기를 관리합니다.

## 3. Single-bus 통신 순서

### 3.1 MCU Start와 DHT11 응답

1. DATA의 Idle 상태는 Pull-up에 의해 High입니다.
2. MCU가 PC4를 Output으로 바꾸고 18 ms 이상 Low를 출력합니다.
3. MCU가 High를 20~40 us 출력한 뒤 PC4를 Input으로 바꾸어 Bus를 놓습니다.
4. DHT11이 약 80 us Low 응답을 출력합니다.
5. DHT11이 약 80 us High 준비 신호를 출력한 뒤 40 bit Data를 전송합니다.

수업 코드는 `20 ms Low → 20 us High → Input` 순서로 구현했습니다.

```c
dht11GpioMode(dht, OUTPUT);
HAL_GPIO_WritePin(dht->port, dht->pin, GPIO_PIN_RESET);
HAL_Delay(20U);
HAL_GPIO_WritePin(dht->port, dht->pin, GPIO_PIN_SET);
delay_us(20U);
dht11GpioMode(dht, INPUT);
```

### 3.2 Data Bit 판별

각 Bit는 약 50 us Low로 시작하며, 뒤따르는 High Pulse의 길이가 값이 됩니다.

| Data | High Pulse | 수업 코드 판별 범위 |
|---|---:|---:|
| `0` | 약 26~28 us | 20 us 초과, 30 us 미만 |
| `1` | 약 70 us | 65 us 초과, 85 us 미만 |

개선본은 경계 오차에 덜 민감하도록 50 us를 Threshold로 사용하고, 모든 Low/High 대기에 110 us Timeout을 적용합니다.

## 4. 40 bit Data와 Checksum

DHT11은 MSB부터 다음 순서의 5 Byte를 전송합니다.

```text
Byte 0: 습도 정수부
Byte 1: 습도 소수부
Byte 2: 온도 정수부
Byte 3: 온도 소수부
Byte 4: Checksum
```

Checksum은 앞 네 Byte 합의 하위 8 bit와 같아야 합니다.

```text
checksum = (humidity_integer + humidity_decimal
          + temperature_integer + temperature_decimal) & 0xFF
```

수업에서는 Debugger에서 `pulse[40]` 배열을 임시로 관찰하여 Bit 배열을 확인했고, Terminal에서 정상 출력과 `checkSum Error`가 반복되는 상황을 함께 기록했습니다. 이 흔적은 Timing 오차나 배선 상태가 Data 무결성에 직접 영향을 준다는 Debugging 근거입니다.

## 5. TIM11을 1 us Counter로 설정하기

수업 Clock Tree에서 TIM11 입력 Clock은 100 MHz입니다.

```text
TIM11CLK = 100,000,000 Hz
PSC      = 99
ARR      = 65,535

f_CNT = TIM11CLK / (PSC + 1)
      = 100,000,000 / 100
      = 1,000,000 Hz

1 Count = 1 us
Overflow = 65,536 us = 65.536 ms
```

이 Timer는 Update Interrupt를 발생시키기 위한 용도가 아니라 실행 중 `TIM11_CNT`를 읽는 자유 실행 Counter로 사용합니다. 따라서 NVIC Interrupt Enable은 필요하지 않습니다. `delay_us()`는 CNT를 0으로 만든 뒤 목표 Count에 도달할 때까지 Polling합니다.

```c
__HAL_TIM_SET_COUNTER(&htim11, 0U);
while (__HAL_TIM_GET_COUNTER(&htim11) < us)
{
}
```

TIM11은 16-bit Up-counter이므로 1 MHz에서 한 번에 측정할 수 있는 범위는 65.535 ms까지입니다. 이번 DHT11의 20 ms Start Low와 100 us 이하 Pulse 측정에는 충분합니다.

## 6. GPIO Output/Input 전환

MCU가 Start 신호를 만들 때는 PC4를 Output Push-Pull로 사용하고, DHT11이 응답을 시작하기 전에 Input으로 바꿉니다.

| 단계 | PC4 Mode | 주체 |
|---|---|---|
| Idle | Input + 외부 Pull-up | Bus High 유지 |
| Start Low/High | GPIO Output Push-Pull | STM32 |
| Response와 40 bit Data | GPIO Input, No Pull | DHT11 |

`HAL_GPIO_Init()`을 통신 과정 중 다시 호출하면서 `GPIOC_MODER`가 Output과 Input 사이에서 변경됩니다. `HAL_GPIO_WritePin()`은 `GPIOC_BSRR`를 통해 Start Level을 Set/Reset하고, `HAL_GPIO_ReadPin()`은 `GPIOC_IDR`에서 현재 Data Level을 읽습니다.

## 7. 버전 구성

| 버전 | 성격 | 내용 |
|---|---|---|
| `VER1_Reconstructed_Lecture` | 실제 수업 코드 복원본 | `delay_us.c/.h`, `dht11.c/.h`, 20~30/65~85 us 구간 판별, 2초 Blocking Sampling과 `printf()` 출력을 보존했습니다. |
| `VER2_Improved_Timeout_Checked` | 별도 개선본 | 모든 응답·Data Edge Timeout, 단계별 오류 상태, 50 us Threshold, Checksum 통과 후 값 갱신, Timer Handle 주입과 `HAL_GetTick()` 기반 2초 Scheduling을 추가했습니다. |

두 버전 모두 CubeMX/CubeIDE 생성 형식의 전체 `main.c`를 사용합니다. 사용자 Header는 `USER CODE Includes`, DHT11 전역 Handle은 `PV`, 초기화는 `USER CODE 2`, Main Loop 측정은 `USER CODE 3`, UART `printf()` Retarget 함수는 `USER CODE 4`에 배치했습니다.

## 8. 수업 코드에서 확인할 점

### 8.1 응답 Timeout 뒤에도 계속 진행

원본은 첫 80 us Low/High 대기에서 100 us를 넘으면 `break`하지만 실패 상태를 저장하지 않습니다. 이후 40 bit 수신으로 계속 진입하므로, Sensor가 응답하지 않는 경우 뒤의 무제한 대기에서 멈출 수 있습니다.

### 8.2 40 bit 수신 구간의 무제한 대기

각 Bit의 Low와 High를 기다리는 두 `while`문에는 Timeout이 없습니다. 배선 단선이나 Pulse 누락이 발생하면 함수가 반환하지 않을 수 있습니다. 개선본은 모든 Edge 대기를 110 us로 제한하고 오류 종류를 반환합니다.

### 8.3 좁은 Pulse 범위와 기본값 0

원본은 High Pulse가 20~30 us 또는 65~85 us에 포함될 때만 값을 기록합니다. 어느 구간에도 속하지 않으면 초기값 0이 남습니다. 개선본은 50 us Threshold로 구분하되, High 상태가 110 us를 넘으면 별도 오류로 처리합니다.

### 8.4 Checksum 이전 값 갱신

원본은 Checksum을 확인하기 전에 구조체의 온·습도 값을 갱신합니다. Checksum이 실패해도 잘못된 값이 Handle에 남을 수 있습니다. 개선본은 Checksum이 일치한 경우에만 마지막 정상값을 갱신합니다.

### 8.5 전체 2초 Blocking Delay

원본의 `HAL_Delay(2000)`은 DHT11의 Sampling 조건을 만족하지만 Main Loop 전체를 2초 동안 멈춥니다. 개선본은 2초 Scheduling을 `HAL_GetTick()`으로 바꾸었습니다. 다만 DHT11의 약 4 ms 통신 자체는 정확한 us Timing을 위해 짧은 Polling 구간으로 유지했습니다.

## 9. CubeMX·HAL·Register 연결

| CubeMX/HAL | 주요 Register | 의미 |
|---|---|---|
| PC4 GPIO Input/Output | `GPIOC_MODER` | Start 출력과 Sensor 입력 사이의 Mode 전환 |
| Output Push-Pull | `GPIOC_OTYPER` | Start 신호를 Push-Pull로 출력 |
| No Pull | `GPIOC_PUPDR` | 외부 5 kΩ Pull-up 사용 |
| `HAL_GPIO_WritePin()` | `GPIOC_BSRR` | Start Low/High를 Atomic Set/Reset |
| `HAL_GPIO_ReadPin()` | `GPIOC_IDR` | DHT11의 현재 Data Level 판독 |
| TIM11 Prescaler 99 | `TIM11_PSC` | 100 MHz를 1 MHz로 분주 |
| TIM11 Period 65535 | `TIM11_ARR` | 16-bit 최대 Free-running 범위 |
| `__HAL_TIM_SET_COUNTER()` | `TIM11_CNT` Write | Pulse 측정 시작점을 0으로 설정 |
| `__HAL_TIM_GET_COUNTER()` | `TIM11_CNT` Read | 경과 us Count 확인 |
| `HAL_TIM_Base_Start/Stop()` | `TIM11_CR1.CEN` | Counter 시작·정지 |

## 10. 핵심 학습 포인트

- 하나의 GPIO를 통신 단계에 따라 Output과 Input으로 전환하여 양방향 Data 선을 제어했습니다.
- ms 단위 Start 신호와 us 단위 응답·Data Pulse를 서로 다른 시간 기준으로 처리했습니다.
- Timer 입력 Clock, PSC와 CNT의 관계를 계산하여 1 Count를 1 us로 만들었습니다.
- DHT11의 40 bit Frame을 5 Byte로 재조립하고 Checksum으로 Data 무결성을 검증했습니다.
- Sensor 통신에서 연결 오류는 단순한 잘못된 값이 아니라 무한 대기로 이어질 수 있으므로 모든 Edge 대기에 Timeout이 필요합니다.
- Checksum 실패 Data로 마지막 정상 측정값을 덮어쓰지 않는 상태 관리가 중요합니다.
- 긴 Sampling 간격은 Non-blocking Scheduling으로 분리할 수 있지만, 수 us 폭을 Software로 측정하는 핵심 구간은 Interrupt 지연의 영향을 받을 수 있습니다.
- DHT11은 정밀·고속 Sensor가 아니며 측정 범위, 정확도와 최소 Sampling 간격을 고려하여 환경 모니터링 수준에 사용해야 합니다.

## 11. 검증 범위

- 메일에 보관된 DHT11 통신 Timing, Pinout, CubeMX TIM11 설정, Driver 코드, Debugger의 40 bit 배열과 Terminal 출력 화면을 서로 대조했습니다.
- DHT11 자료의 전원·측정 범위·Pull-up·Start/Response·Bit Timing·40 bit Frame·Checksum·Sampling 조건을 코드와 연결했습니다.
- STM32F411RE RM0383과 UM1725를 기준으로 TIM11의 16-bit PSC/CNT/ARR, GPIO Mode 전환과 HAL GPIO/Timer 동작을 정적 검토했습니다.
- GitHub에는 코드와 설정 문서만 보존하고, 실제 수업 화면은 Notion에 배치합니다.
- 두 버전의 `main.c`, `dht11.c`와 `delay_us.c`는 HAL Stub을 이용한 C 문법·경고 검사를 수행합니다.
- 원본 `.ioc`, 생성된 `tim.c/.h`, `gpio.c/.h`, `usart.c/.h`와 전체 CubeIDE Project는 현재 보관본에 포함되지 않았습니다.
- 이번 정리 과정에서 CubeIDE 전체 재빌드와 실물 Board 재시험은 수행하지 않았습니다.

## 참고 문서

- STMicroelectronics, *RM0383: STM32F411xC/E Reference Manual*, Rev 3
- STMicroelectronics, *UM1725: Description of STM32F4 HAL and Low-layer Drivers*, Rev 8
- D-Robotics, *DHT11 Humidity & Temperature Sensor*
- 메일 보관 자료, *[STM32 학습 기록] FW: LAB_DHT11*
