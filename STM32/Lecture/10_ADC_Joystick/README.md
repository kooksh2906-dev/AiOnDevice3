# 09. ADC and SZH-EK056 Joystick

STM32F411RE의 ADC1로 SZH-EK056 2축 조이스틱 모듈의 아날로그 출력을 읽은 학습 기록입니다. 한 축을 Polling과 Interrupt 방식으로 읽은 뒤, Scan Mode와 Circular DMA를 사용하여 X/Y 두 축을 연속 취득하는 순서로 확장했습니다.

`SZH-EK056`은 판매 정보에서 X/Y 아날로그 출력과 Z축 눌림 Switch를 갖는 PS2형 조이스틱 모듈로 확인됩니다. 다만 제조사 정식 데이터시트는 확보하지 못했으므로, 저항값·허용 전압·Connector Pin 순서처럼 공식 문서로 확인되지 않은 수치는 임의로 단정하지 않습니다. 이번 실습에서 확인된 ADC X/Y 축만 코드에 반영하고 Z축 Switch는 범위에서 제외합니다.

## 1. 실제 실습 구성

| 구분 | 설정·연결 | 역할 |
|---|---|---|
| Board | NUCLEO-F411RE | ADC 변환과 USART2 출력 |
| Joystick X | PA7 / ADC1_IN7 / Rank 1 | `adcValue[0]`에 저장 |
| Joystick Y | PA6 / ADC1_IN6 / Rank 2 | `adcValue[1]`에 저장 |
| Joystick 전원 | 3.3 V, GND | ADC 입력이 STM32의 기준 전압 범위를 넘지 않도록 3.3 V 사용 |
| USART2 | PA2/PA3, ST-LINK VCP | Raw ADC 값과 계산값 출력 |
| DMA | DMA2 Stream 0, Peripheral-to-Memory, Circular | 두 채널 변환 결과를 16-bit 배열로 반복 전송 |

모듈마다 Silkscreen과 Connector 순서가 다를 수 있으므로 재배선할 때에는 `VCC`, `GND`, X축 출력, Y축 출력, Switch 표기를 실물에서 다시 확인해야 합니다.

## 2. 12-bit ADC와 전압 환산

STM32F411의 ADC는 Successive Approximation 방식이며, 이번 실습에서는 12-bit·Right Alignment를 사용했습니다. 따라서 변환 결과 범위는 `0~4095`입니다.

```text
ADC code range = 0 ... (2^12 - 1) = 0 ... 4095

Vin ≈ ADC_code × VDDA / 4095
```

수업 Polling 코드는 `VDDA = 3.3 V`로 가정하여 다음과 같이 전압을 계산했습니다.

```c
adcVoltage = 3.3f * ((float)adcValue / 4095.0f);
```

이 값은 명목상 환산값입니다. 실제 정확도를 높이려면 Board의 VDDA, Joystick 중심 편차, ADC Offset·Gain 오차와 전원 Noise를 함께 고려해야 합니다.

## 3. 학습 흐름

### 3.1 Polling: 단일 축

Software Trigger로 변환을 시작하고, 변환 완료를 기다린 뒤 ADC Data Register 값을 읽습니다.

```c
HAL_ADC_Start(&hadc1);
HAL_ADC_PollForConversion(&hadc1, 500U);
adcValue = (uint16_t)HAL_ADC_GetValue(&hadc1);
```

수업 설정은 Scan Disabled, Continuous Disabled, Rank 1 Channel 7, Sampling Time 3 cycles입니다. `HAL_ADC_PollForConversion()`은 흐름을 이해하기 쉽지만 완료 대기 동안 현재 실행 흐름이 Block됩니다. 실제 변환 시간보다 수업 코드의 `HAL_Delay(500)`이 출력 주기를 지배합니다.

### 3.2 Interrupt: 단일 축

`HAL_ADC_Start_IT()`로 변환과 EOC Interrupt를 활성화하고, 변환 완료 Callback에서 값을 읽습니다.

```c
void HAL_ADC_ConvCpltCallback(ADC_HandleTypeDef *hadc)
{
    if (hadc->Instance == ADC1)
    {
        adcValue = (uint16_t)HAL_ADC_GetValue(hadc);
    }
}
```

수업 화면에서는 Continuous Conversion을 사용하므로 시작 함수는 한 번 호출하고 이후 변환 완료마다 Callback이 실행됩니다. 복원본은 Callback 정의를 사용자 코딩 기준에 맞게 `USER CODE BEGIN 4`로 옮기고 ADC1 Instance를 확인합니다.

### 3.3 Circular DMA: X/Y 두 축

ADC Scan Mode가 Rank 1 Channel 7과 Rank 2 Channel 6을 순서대로 변환하고, DMA가 각 결과를 SRAM 배열로 옮깁니다.

```text
Rank 1: ADC1_IN7 (PA7, X) -> adcValue[0]
Rank 2: ADC1_IN6 (PA6, Y) -> adcValue[1]
```

```c
HAL_ADC_Start_DMA(&hadc1, (uint32_t *)adcValue, 2U);
```

DMA Peripheral Data Width와 Memory Data Width는 모두 Half Word로 설정합니다. 12-bit 결과가 16-bit 배열 원소에 저장되며, Memory Increment가 다음 배열 원소로 이동합니다. Circular Mode와 DMA Continuous Requests를 함께 사용하면 두 채널 Sequence가 끝난 뒤 같은 배열을 계속 갱신합니다.

## 4. ADC Clock와 Sampling Time

실습 Clock Tree에서 PCLK2는 100 MHz이고 ADC Prescaler는 4입니다.

```text
ADCCLK = PCLK2 / 4 = 25 MHz
```

12-bit 변환 시간은 Reference Manual의 식 `Sampling time + 12 ADC cycles`로 계산합니다.

| 설정 | 한 채널 변환 | 25 MHz 기준 |
|---|---:|---:|
| Polling/Interrupt, 3 cycles | 3 + 12 = 15 cycles | 약 0.60 us |
| DMA, 480 cycles | 480 + 12 = 492 cycles | 약 19.68 us |
| DMA 2채널 Sequence | 492 × 2 = 984 cycles | 약 39.36 us |

긴 Sampling Time은 변환 속도를 낮추지만, Potentiometer 분압 출력과 ADC Sample-and-Hold Capacitor가 안정될 시간을 늘립니다. 수업의 480-cycle 설정은 빠른 조작 검출보다 안정적인 두 축 판독에 여유를 둔 설정으로 볼 수 있습니다.

## 5. 버전 구성

| 버전 | 성격 | 내용 |
|---|---|---|
| `01_Polling/VER1_Reconstructed_Lecture` | 수업 코드 복원본 | PA7/ADC1_IN7 한 축의 Polling, 3.3 V 환산과 UART 출력 |
| `02_Interrupt/VER1_Reconstructed_Lecture` | 수업 코드 복원본 | PA7/ADC1_IN7 한 축의 Continuous Conversion과 ADC EOC Callback |
| `03_DMA/VER1_Reconstructed_Lecture` | 수업 코드 복원본 | PA7·PA6 두 축의 Scan Mode와 Circular DMA, Raw X/Y 출력 |
| `03_DMA/VER2_Improved_Calibrated` | 별도 개선본 | 부팅 시 중심 평균, Dead Zone, 간단한 IIR Filter와 -1000~1000 정규화 |

강사 제공 참조 코드는 전체 Project 원본이 아니라 보관된 코드와 화면을 바탕으로 한 자료이므로 `Original`이 아닌 `Reconstructed`로 표시했습니다. 개선본의 보정·필터 값은 교육용 초기값이며 SZH-EK056 실물에서 재시험한 값은 아닙니다.

## 6. 개선본의 좌표 처리

Joystick 중심은 기계 오차와 Potentiometer 편차 때문에 정확히 2048이 아닐 수 있습니다. 개선본은 부팅 직후 Stick을 놓은 상태에서 32개 Sample의 평균을 중심으로 저장합니다.

1. Circular DMA를 시작합니다.
2. X/Y 배열을 32회 읽어 중심 평균을 구합니다.
3. IIR Filter로 Raw 값의 짧은 흔들림을 완화합니다.
4. 중심 주변 ±150 count는 0으로 처리합니다.
5. 중심에서 각 끝점까지를 X/Y 각각 `-1000~1000`으로 정규화합니다.

Dead Zone과 Filter는 Noise를 줄이는 대신 작은 움직임에 대한 민감도와 응답 속도를 낮춥니다. 실제 제품에서는 중심값, 끝점, 축 방향을 기구 조립 상태에서 다시 측정해야 합니다.

## 7. CubeMX·HAL·Register 연결

| CubeMX/HAL | 주요 Register/동작 | 의미 |
|---|---|---|
| PA7 ADC1_IN7, PA6 ADC1_IN6 | GPIO Analog Mode | Digital Input/Output 경로를 끄고 ADC 입력으로 사용 |
| ADC Prescaler `/4` | `ADC_CCR.ADCPRE` | PCLK2를 ADCCLK로 분주 |
| 12-bit | `ADC_CR1.RES` | 12-bit 변환 해상도 |
| Scan Enabled | `ADC_CR1.SCAN` | Regular Group의 여러 Rank를 순서대로 변환 |
| Continuous Enabled | `ADC_CR2.CONT` | 마지막 Rank 뒤 첫 Rank부터 반복 |
| Rank/Length | `ADC_SQRx` | IN7 → IN6 순서와 변환 개수 2 설정 |
| Sampling Time | `ADC_SMPR2.SMP6/SMP7` | 채널별 Sample-and-Hold 시간 |
| `HAL_ADC_Start()` | `ADC_CR2.ADON/SWSTART` | Polling 변환 시작 |
| `HAL_ADC_Start_IT()` | EOC Interrupt Enable | 변환 완료 시 ADC IRQ와 Callback 사용 |
| `HAL_ADC_Start_DMA()` | `ADC_CR2.DMA/DDS` + DMA2 Stream 0 | ADC_DR 결과를 배열로 연속 전송 |
| DMA Half Word | `DMA_SxCR.PSIZE/MSIZE` | 12-bit 결과를 16-bit 단위로 전송 |
| DMA Circular | `DMA_SxCR.CIRC` | 배열 끝에서 자동으로 다시 시작 |

## 8. 핵심 학습 포인트

- ADC는 연속적인 전압을 이산적인 Digital Code로 변환하며 해상도와 기준 전압이 환산 단위를 결정합니다.
- Polling, Interrupt와 DMA는 같은 ADC 결과를 얻지만 CPU의 대기·개입 방식이 다릅니다.
- 여러 Analog Channel을 연속 취득할 때 Scan Rank와 DMA 배열 Index의 대응을 정확히 관리해야 합니다.
- DMA의 Half Word 설정은 12-bit ADC 결과를 `uint16_t` 배열에 저장하는 자료형과 일치합니다.
- `volatile`은 DMA가 값을 바꿀 수 있음을 Compiler에 알리지만, 보정·필터·동시성 정책까지 대신하지는 않습니다.
- Joystick은 중심 편차와 Noise가 있으므로 제어 명령으로 사용하기 전에 중심 보정, Dead Zone, Filtering과 정규화가 필요할 수 있습니다.
- 3.3 V ADC 입력에서 모듈 출력이 허용 범위를 넘지 않도록 전원과 배선을 먼저 확인해야 합니다.
- Z축 눌림은 Digital GPIO 입력으로 별도 처리하는 기능이며 이번 실제 ADC 실습 범위에는 포함되지 않았습니다.

## 9. 검증 범위

- 메일에 보관된 CubeMX Pinout·ADC/NVIC/DMA 설정, Polling·Interrupt·DMA 코드와 Tera Term 출력 화면을 서로 대조했습니다.
- STM32F411RE RM0383의 ADC Clock, Scan, Sampling Time, DMA 동작과 UM1725의 Polling·Interrupt·DMA HAL 흐름을 코드에 연결했습니다.
- GitHub에는 코드와 설정 문서만 저장하고 실제 수업 캡처는 Notion에 배치합니다.
- 네 버전의 C Source는 HAL Stub을 사용하여 문법·경고 검사를 수행합니다.
- 원본 `.ioc`, 생성된 `adc.c/.h`, `dma.c/.h`, `gpio.c/.h`, `usart.c/.h`와 전체 CubeIDE Project는 현재 보관본에 포함되지 않았습니다.
- 이번 정리 과정에서 CubeIDE 전체 재빌드와 실물 Board 재시험은 수행하지 않았습니다.

## 참고 문서

- STMicroelectronics, *RM0383: STM32F411xC/E Reference Manual*, Rev 3
- STMicroelectronics, *UM1725: Description of STM32F4 HAL and Low-layer Drivers*, Rev 8
- ICBANQ, [아두이노 PS2 조이스틱 모듈 SZH-EK056](https://www.icbanq.com/P008113513)
- 메일 보관 자료, *[STM32 학습기록] FW: LAB_ADC*

