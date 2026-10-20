# STM32CubeMX / Hardware 설정

## GPIO 출력

| 대상 | Pin | Mode | Output Type | Pull | Speed | 초기 출력 |
|---|---|---|---|---|---|---|
| NUCLEO-F411RE Board LED | PA5 | GPIO Output | Push-Pull | No Pull | Low | Reset |
| 추가 LED | PA6 | GPIO Output | Push-Pull | No Pull | Low | Reset |

- PA5는 원본 학습 기록에서 Board LED가 연결된 Pin으로 사용했습니다.
- PA6은 두 번째 LED 제어 코드에 포함되어 있지만 외부 LED의 실제 배선 기록은 남아 있지 않습니다. PA6 실습 시에는 LED와 전류 제한 저항의 연결을 별도로 확인해야 합니다.
- LED가 Active High로 연결되었다는 코드 흐름을 기준으로 `GPIO_PIN_SET`을 ON, `GPIO_PIN_RESET`을 OFF로 정리했습니다.

## Clock / Time Base

원본 `main.c`에는 HSE Bypass와 PLL 설정을 사용하여 100 MHz System Clock을 구성한 기록이 있습니다. `HAL_Init()` 이후 기본 HAL Time Base가 정상적으로 초기화되어야 `HAL_GetTick()`과 `HAL_Delay()`가 ms 단위로 동작합니다.

이번 보관본에는 원본 `.ioc`가 포함되어 있지 않으므로 다음 항목은 CubeMX 프로젝트를 다시 확보했을 때 최종 대조합니다.

- Board와 MCU Part Number
- PA5 및 PA6의 User Label
- System Clock Source와 Clock Tree
- HAL Time Base Source
- 생성된 `gpio.c`, `main.h`의 Pin Define

## 관련 레지스터

- `RCC_AHB1ENR`: GPIOA Peripheral Clock 활성화
- `GPIOA_MODER`: PA5·PA6을 General-Purpose Output으로 설정
- `GPIOA_OTYPER`: Push-Pull/Open-Drain 선택
- `GPIOA_OSPEEDR`: 출력 속도 선택
- `GPIOA_PUPDR`: Pull-Up/Pull-Down 선택
- `GPIOA_ODR`: 출력 상태
- `GPIOA_BSRR`: 출력 Bit의 원자적 Set/Reset

