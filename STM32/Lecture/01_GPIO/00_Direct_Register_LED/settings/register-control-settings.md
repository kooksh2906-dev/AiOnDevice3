# Register Control Settings

이 실습은 STM32CubeMX의 Pinout, Clock Configuration 또는 Code Generation 기능을 사용하지 않았습니다. 다음 설정을 `main.c`에서 Memory-Mapped Register에 직접 기록했습니다.

## 1. HSE Clock 입력

NUCLEO-F411RE 기본 구성에서는 ST-LINK MCU가 출력한 8 MHz MCO Clock을 대상 STM32F411의 `PH0/OSC_IN`에 공급합니다.

```c
RCC_CR |= RCC_CR_HSEBYP;
RCC_CR |= RCC_CR_HSEON;
while ((RCC_CR & RCC_CR_HSERDY) == 0U) { }
```

- `HSEBYP = 1`: Crystal Resonator가 아닌 외부 Digital Clock 입력
- `HSEON = 1`: HSE Clock 활성화
- `HSERDY`: HSE Clock 안정화 상태

원본 두 버전에는 `HSEBYP` 설정이 없지만 당시 실물 동작 사실을 보존하기 위해 원본은 수정하지 않았습니다. 교정본에서 보드의 기본 MCO 경로에 맞게 보완했습니다.

## 2. PLL과 Bus Clock

| 항목 | 설정 | 결과 |
|---|---:|---:|
| HSE | 8 MHz | PLL Source |
| PLLM | 4 | PLL 입력 2 MHz |
| PLLN | 200 | VCO 400 MHz |
| PLLP | 4 | SYSCLK 100 MHz |
| AHB Prescaler | 1 | HCLK 100 MHz |
| APB1 Prescaler | 2 | PCLK1 50 MHz |
| APB2 Prescaler | 1 | PCLK2 100 MHz |

교정본의 PLLQ는 유효한 Field 값인 8로 설정했지만, VCO 400 MHz를 48 MHz로 정확히 나눌 수 없으므로 USB OTG FS·SDIO처럼 48 MHz 계열 Clock이 필요한 주변장치는 이 Clock Tree에서 사용하지 않습니다.

## 3. Flash Access

NUCLEO-F411RE의 3.3 V 동작 조건과 HCLK 100 MHz를 기준으로 Flash Latency를 3 Wait State로 설정합니다. 교정본에서는 Prefetch, Instruction Cache와 Data Cache도 함께 활성화합니다.

Clock을 100 MHz PLL로 전환하기 전에 Flash Latency를 먼저 설정하여 고속 Clock에서의 Flash 접근 조건을 만족시킵니다.

## 4. GPIOA PA5

| 설정 대상 | 값 | 의미 |
|---|---|---|
| `RCC_AHB1ENR.GPIOAEN` | 1 | GPIOA Bus Clock 활성화 |
| `GPIOA_MODER.MODER5` | `01` | General-purpose Output |
| `GPIOA_OTYPER.OT5` | 0 | Push-Pull |
| `GPIOA_OSPEEDR.OSPEED5` | `00` | Low Speed |
| `GPIOA_PUPDR.PUPD5` | `00` | No Pull |
| `GPIOA_ODR.ODR5` | Toggle | LD2 출력 반전 |

원본은 `MODER5` 이외의 GPIO 설정을 Reset Value에 의존합니다. 교정본은 재진입이나 선행 설정의 영향을 줄이기 위해 해당 Field를 Clear한 뒤 명시적으로 구성합니다.

## 5. SysTick Polling

```text
Reload + 1 = 100,000 Tick
100,000 Tick / 100,000,000 Tick/s = 0.001 s = 1 ms
```

- `CLKSOURCE = 1`: Processor Clock 사용
- `ENABLE = 1`: SysTick Counter 활성화
- `TICKINT = 0`: Interrupt 미사용
- `COUNTFLAG`: Reload 발생 여부를 Polling으로 확인

따라서 `delay_ms(1000)`은 약 1초 동안 현재 실행 흐름을 대기시키는 Blocking Delay입니다.
