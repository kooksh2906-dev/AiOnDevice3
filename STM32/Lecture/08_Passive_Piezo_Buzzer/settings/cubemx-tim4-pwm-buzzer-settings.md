# STM32CubeMX TIM4 PWM Buzzer 설정

메일에 보관된 CubeMX 화면과 코드에서 확인한 설정입니다. 원본 `.ioc`가 없으므로 Clock Tree와 생성 코드의 모든 항목을 완전히 재현한 문서가 아니라, 확인 가능한 설정과 계산 근거를 정리한 자료입니다.

## 1. Pin과 배선

| 항목 | 설정 |
|---|---|
| PWM Pin | PB6 |
| Alternate Function | AF2 TIM4_CH1 |
| 부저 `+` | PB6 |
| 부저 `-` | GND |
| GPIO Mode | Alternate Function Push-Pull |
| Pull | No Pull |

원본 Nucleo Connector 화면에서 PB6은 Arduino D10 위치와 Morpho Connector에 표시되어 있습니다. 실제 Board Revision과 Connector Pin을 다시 확인한 뒤 배선합니다.

## 2. TIM4 Mode

| 항목 | 원본 설정 |
|---|---|
| Clock Source | Internal Clock |
| Slave Mode | Disable |
| Trigger Source | Disable |
| Channel 1 | PWM Generation CH1 |
| Channel 2~4 | Disable |
| One Pulse Mode | Disable |

## 3. Counter와 PWM Channel

| 항목 | 원본 설정 |
|---|---:|
| Prescaler | 1999 |
| Counter Mode | Up |
| Counter Period | 999 |
| Clock Division | No Division |
| Auto-reload Preload | Disable |
| PWM Mode | PWM mode 1 |
| Pulse | 499 |
| Output Compare Preload | Enable |
| Fast Mode | Disable |
| Channel Polarity | High |

실행 코드에서는 음계에 따라 PSC를 바꾸고 `CCR1=500`을 사용합니다.

## 4. Clock 계산

원본 System Clock 설정은 HCLK 100 MHz, APB1 Prescaler `/2`에 해당합니다.

```text
PCLK1   = 50 MHz
TIM4CLK = 2 × PCLK1 = 100 MHz
```

STM32F411에서는 APB Prescaler가 1이 아닐 때 해당 APB Timer Clock이 일반적으로 PCLK의 두 배가 됩니다.

초기 CubeMX 값의 PWM 주파수는 다음과 같습니다.

```text
f_PWM = 100,000,000 / ((1999 + 1) × (999 + 1))
      = 50 Hz
```

이 초기값은 Timer Channel의 기본 출력을 구성하기 위한 값이며, 실제 음계 출력에서는 PSC가 음계 값으로 변경됩니다.

## 5. 음계 PSC 계산

ARR를 999로 고정하면 목표 주파수에 필요한 PSC는 다음과 같이 구합니다.

```text
PSC ≈ TIM4CLK / (target_frequency × (ARR + 1)) - 1
```

| 음계 | 목표 주파수 | 원본 PSC | 계산 주파수 |
|---|---:|---:|---:|
| A4 | 440 Hz | 226 | 약 440.53 Hz |
| B4 | 494 Hz | 202 | 약 492.61 Hz |
| C5 | 523 Hz | 190 | 약 523.56 Hz |
| D5 | 587 Hz | 169 | 약 588.24 Hz |
| E5 | 659 Hz | 151 | 약 657.89 Hz |
| F#5 | 740 Hz | 134 | 약 740.74 Hz |
| G5 | 784 Hz | 127 | 약 781.25 Hz |
| A5 | 880 Hz | 113 | 약 877.19 Hz |

정수 Prescaler를 사용하므로 목표 주파수와 실제 주파수 사이에 작은 오차가 생깁니다.

## 6. Duty와 출력 제어

PWM Mode 1의 Up-counting에서는 `CNT < CCR1`일 때 Channel이 Active입니다.

```text
ARR + 1 = 1000 counts
CCR1    = 500 counts
Duty    = 500 / 1000 × 100 = 50%
```

- `CCR1=500`: 약 50% Duty로 음 출력
- `CCR1=0`: High 구간이 없어 무음

## 7. 코드 생성 후 확인

CubeMX가 생성한 Project에서는 다음 항목을 확인합니다.

1. `tim.c`의 `MX_TIM4_Init()`에서 PSC=1999, ARR=999, PWM1과 Pulse=499가 설정되어 있는지 확인합니다.
2. `HAL_TIM_MspPostInit()`에서 PB6이 AF2 TIM4로 설정되는지 확인합니다.
3. `main.c`의 Peripheral 초기화 뒤 `HAL_TIM_PWM_Start(&htim4, TIM_CHANNEL_1)`을 호출합니다.
4. 음계 전환 코드가 PSC를 변경한 뒤 Update Event를 언제 발생시키는지 확인합니다.
5. 부저 정격과 GPIO 구동 전류가 맞지 않으면 Driver를 추가합니다.

## 8. 보관 범위

- GitHub에는 `main.c`, `buzzer.c/.h`와 이 설정 문서만 보존합니다.
- 실제 CubeMX 설정·Pinout·IDE 코드 캡처는 Notion에 보존합니다.
- 원본 `.ioc`와 전체 생성 Project가 확보되면 Clock Tree, Pin Speed와 생성 초기화 코드를 추가 대조합니다.
