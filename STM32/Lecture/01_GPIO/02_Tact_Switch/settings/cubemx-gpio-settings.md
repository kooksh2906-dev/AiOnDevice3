# STM32CubeMX / Hardware 설정

## Polling 실습 설정

| 대상 | Pin | Mode | Pull | Active Level | 용도 |
|---|---|---|---|---|---|
| NUCLEO-F411RE User Button | PC13 | GPIO Input | No Pull | High | Tact Switch 입력 |
| NUCLEO-F411RE Board LED | PA5 | GPIO Output Push-Pull | No Pull | High | 입력 확인 및 Toggle 출력 |

## 설정 근거와 범위

- 보관된 EXTI 실습 화면에서 PC13과 PA5를 사용한 사실을 확인했고, 공식 Board 회로도에서 PC13의 외부 Pull-down과 Active-High Button 연결을 확인했습니다.
- 이번 Polling 복원본에서는 PC13의 Mode만 `External Interrupt Mode`가 아닌 `GPIO_Input`으로 설정합니다.
- Board의 외부 Pull-down을 사용하므로 내부 Pull은 `No Pull`, Released는 Low, Pressed는 High입니다.
- 실제 Board 회로 또는 외부 Switch 배선이 다른 경우 Active Level과 Pull 설정을 함께 변경해야 합니다.

## 관련 레지스터

- `RCC_AHB1ENR`: GPIOA와 GPIOC Peripheral Clock 활성화
- `GPIOC_MODER`: PC13을 General-Purpose Input으로 설정
- `GPIOC_PUPDR`: PC13 No Pull 설정(Board 외부 Pull-down 사용)
- `GPIOC_IDR`: PC13 입력 Level 판독
- `GPIOA_MODER`: PA5를 General-Purpose Output으로 설정
- `GPIOA_OTYPER`: PA5 Push-Pull 설정
- `GPIOA_BSRR`: PA5 출력 Set/Reset

## 추후 원본 프로젝트 확보 시 확인할 항목

- MCU와 Board Part Number
- PC13 및 PA5의 User Label
- 생성된 `gpio.c`와 `main.h`의 Pin Define
- Board Revision과 User Button 회로의 실제 Active Level
- `.ioc`의 Pin Mode, Pull 및 NVIC 설정
