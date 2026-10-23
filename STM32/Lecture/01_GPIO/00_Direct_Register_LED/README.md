# Direct Register LED Control

STM32CubeMX와 HAL 드라이버를 사용하지 않고 STM32F411RE의 Memory-Mapped Register에 직접 값을 기록하여 NUCLEO-F411RE의 PA5 온보드 LED(LD2)를 점멸한 학습 기록입니다.

이 실습은 STM32 주변장치 학습의 마지막 단계이자 SoC 과정에 들어가기 전 수행했습니다. 하드웨어 담당자로부터 MCU 데이터시트와 레퍼런스 매뉴얼을 전달받았다는 상황을 가정하고, Clock Tree와 GPIO를 저수준에서 직접 구성하는 과정을 통해 HAL 기반 Hardware Abstraction이 제공하는 편의성과 중요성을 확인하는 데 목적이 있습니다.

두 원본 버전은 당시 NUCLEO-F411RE 실물 보드에서 컴파일 오류 없이 정상 동작했습니다. 원본은 학습 이력 보존을 위해 수정하지 않았으며, 데이터시트와 레퍼런스 매뉴얼에 맞춘 보완 사항은 별도 교정본에 반영했습니다.

## 하드웨어 및 클럭 조건

- Board: NUCLEO-F411RE
- Target MCU: STM32F411RE, Arm Cortex-M4
- LED: PA5, 온보드 LD2, Active-High
- HSE 입력: ST-LINK MCU의 MCO에서 공급되는 8 MHz 외부 디지털 클럭
- System Clock: PLL을 이용한 100 MHz
- CubeMX/HAL: 사용하지 않음

NUCLEO-F411RE 기본 보드에서는 대상 MCU용 X3 HSE Crystal이 일반적으로 실장되지 않고, ST-LINK 측 Clock을 MCO로 출력하여 STM32F411의 `OSC_IN`에 공급합니다. 따라서 교정본에서는 외부 디지털 클럭 입력 조건에 맞게 `HSEBYP`를 설정합니다.

## 버전 구성

| 버전 | 지연 방식 | 보존·작성 기준 | 검증 상태 |
|---|---|---|---|
| `VER1_Original_Busy_Wait` | `for` 반복문 Busy-wait | 공유된 원본을 그대로 보존 | 당시 실물 동작 확인 |
| `VER2_Original_SysTick_Polling` | SysTick `COUNTFLAG` Polling | 공유된 원본을 그대로 보존 | 당시 실물 동작 확인 |
| `VER3_Corrected_SysTick_Polling` | SysTick `COUNTFLAG` Polling | Register Field와 Clock 전환 절차를 보완 | 정적 검토 및 C 문법 검사 |

이 실습은 CubeMX가 생성한 프로젝트가 아니라 CubeIDE에서 직접 레지스터를 구성한 학습이므로, 원본의 독립형 `main.c` 형식을 유지합니다. 다른 HAL 실습에 적용한 `USER CODE BEGIN/END` 배치 규칙의 예외입니다.

## Clock Tree 계산

원본 두 버전은 다음 PLL 설정을 사용합니다.

```text
HSE 8 MHz / PLLM 4 = PLL 입력 2 MHz
PLL 입력 2 MHz × PLLN 200 = VCO 400 MHz
VCO 400 MHz / PLLP 4 = SYSCLK 100 MHz
```

- VER1: HCLK 100 MHz, PCLK1 50 MHz, PCLK2 100 MHz
- VER2: HCLK 100 MHz, PCLK1 25 MHz, PCLK2 50 MHz
- VER3: HCLK 100 MHz, PCLK1 50 MHz, PCLK2 100 MHz

VER2의 APB 분주 값은 허용 범위 안에서 동작하지만, 원본 주석의 `25MHz 최대`, `50MHz 최대`는 해당 버전의 설정 결과를 의미합니다. STM32F411의 최대 APB Clock은 PCLK1 50 MHz, PCLK2 100 MHz입니다.

## 주요 Register

| Register | 역할 |
|---|---|
| `RCC_CR` | HSE Bypass·Enable, HSE Ready, PLL Enable·Ready 제어 |
| `RCC_PLLCFGR` | PLLM, PLLN, PLLP, PLLQ 및 HSE Clock Source 설정 |
| `RCC_CFGR` | AHB/APB Prescaler와 System Clock Source 선택·상태 확인 |
| `FLASH_ACR` | 100 MHz Flash 접근을 위한 Latency와 ART 기능 설정 |
| `RCC_AHB1ENR` | GPIOA Peripheral Clock 활성화 |
| `GPIOA_MODER` | PA5를 General-purpose Output으로 설정 |
| `GPIOA_ODR` | PA5 출력 값을 Read-Modify-Write 방식으로 Toggle |
| `SysTick LOAD/VAL/CTRL` | 1 ms Reload 값, 현재 Counter 초기화 및 COUNTFLAG Polling |

## 지연 방식 비교

### VER1 - `for` Busy-wait

```c
GPIOA_ODR ^= GPIOA_ODR_ODR5;
for (volatile int i = 0; i < 10000000; i++);
```

반복문이 끝날 때까지 CPU를 점유합니다. 반복 횟수는 확인할 수 있지만 실제 지연 시간은 Compiler 최적화, 생성 명령어와 실행 Cycle에 따라 달라지므로 코드만으로 정확한 ms 값을 확정할 수 없습니다.

### VER2·VER3 - SysTick Polling

100 MHz Processor Clock에서 `LOAD = 100000 - 1`로 설정하면 COUNTFLAG가 1 ms마다 발생합니다. `delay_ms(1000)`은 약 1,000 ms마다 LED 출력을 반전하므로 점등과 소등을 포함한 전체 점멸 주기는 약 2초입니다.

SysTick을 사용하더라도 COUNTFLAG가 설정될 때까지 Loop에서 계속 기다리므로 이 구현은 Interrupt나 Non-Blocking 방식이 아니라 Blocking Polling입니다.

## 원본 보존과 교정본의 차이

원본 코드는 실제 학습 결과이므로 다음 특성도 수정하지 않고 보존했습니다.

- `RCC_CFGR`와 `GPIOA_MODER`를 OR 연산으로 설정하여 Reset Value를 전제로 함
- Clock Source 요청 비트 `SW`를 읽어 실제 전환 상태 `SWS`를 확인한 것처럼 작성됨
- ST-LINK MCO 입력에 필요한 `HSEBYP`가 명시되지 않음
- `RCC_PLLCFGR` 전체 대입 과정에서 PLLQ Field가 0으로 설정됨
- VER2의 SysTick Register Macro가 동일한 내용으로 두 번 선언됨
- GPIO Output Type, Speed와 Pull 상태를 Reset Value에 의존함

교정본에서는 원본의 학습 흐름을 유지하면서 다음을 보완했습니다.

- `HSEBYP`를 `HSEON`보다 먼저 설정
- PLLM/N/P/Q Field를 Mask한 뒤 명시적으로 설정
- AHB/APB Prescaler Field를 Clear한 뒤 필요한 값 설정
- Flash 3 Wait State와 Prefetch·Instruction Cache·Data Cache 설정
- System Clock 전환 후 `SWS` Field로 실제 PLL 적용 여부 확인
- PA5의 Output Mode, Push-Pull, Low Speed와 No Pull을 명시적으로 설정
- 중복 SysTick Macro 제거와 의미 있는 Bit Mask 사용

교정본도 Register Ready 대기 중 Timeout을 두지 않은 학습용 예제입니다. 실제 제품 코드에서는 Clock Startup Failure에 대한 Timeout과 Fallback 정책을 별도로 설계해야 합니다.

## 핵심 학습 포인트

- Peripheral Register는 Memory-Mapped I/O 주소와 `volatile` 접근을 통해 직접 제어할 수 있습니다.
- GPIO를 사용하기 전에 Bus Clock을 활성화해야 하며, Pin Mode와 출력 Register는 서로 다른 역할을 담당합니다.
- PLL 출력 주파수는 HSE, PLLM, PLLN과 PLLP의 관계를 계산한 뒤 각 Bus의 최대 Clock을 넘지 않도록 Prescaler를 설정해야 합니다.
- Clock Source 선택 요청 `SW`와 실제 적용 상태 `SWS`는 구분하여 확인해야 합니다.
- 단순 반복문 Delay는 실행 환경에 따라 시간이 달라지지만 SysTick은 Core Clock을 기준으로 반복 가능한 시간 단위를 만들 수 있습니다.
- 직접 Register 제어 과정을 통해 CubeMX와 HAL이 Clock·GPIO 초기화, Field Masking과 상태 확인을 대신 수행한다는 의미를 이해할 수 있습니다.
- HAL을 사용하지 않더라도 Startup Code, Vector Table과 Linker Script 같은 MCU 실행 기반은 여전히 필요합니다.

## 검증 범위

- VER1·VER2: 수업 당시 NUCLEO-F411RE 실물 동작 및 오류 없는 실행 확인
- 이번 정리: 원본과 교정본의 C 문법 검사 및 공식 문서 기반 정적 검토
- 미수행: 현재 환경에서의 CubeIDE 전체 재빌드와 교정본 실물 보드 재시험

## 참고 자료

- [STM32F411xC/E Reference Manual RM0383](https://www.st.com/resource/en/reference_manual/rm0383-stm32f411xce-advanced-armbased-32bit-mcus-stmicroelectronics.pdf)
- [STM32F411xC/E Datasheet DS10314](https://www.st.com/resource/en/datasheet/stm32f411ce.pdf)
- [STM32 Nucleo-64 Boards User Manual UM1724](https://www.st.com/resource/en/user_manual/dm00105823.pdf)
- [NUCLEO-F411RE Board Schematic](https://www.st.com/resource/en/schematic_pack/mb1136-default-c03_schematic.pdf)
