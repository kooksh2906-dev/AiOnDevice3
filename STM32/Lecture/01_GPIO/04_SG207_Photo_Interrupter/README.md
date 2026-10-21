# 04. SG-207 Photo Interrupter

STM32F411RE의 PC4를 GPIO Input으로 설정하고, 투과형 포토인터럽터 SG-207의 출력 상태를 Polling으로 읽은 실제 실습 기록입니다. 개선 버전이나 EXTI 확장 코드는 추가하지 않고, 보관된 CubeMX·코드·디버거 화면에서 확인되는 범위만 정리했습니다.

## 1. SG-207 동작 원리

SG-207은 5 mm Slit을 사이에 둔 GaAs 적외선 LED와 포토트랜지스터로 구성된 투과형 포토인터럽터입니다. Slit 사이의 물체 유무에 따라 포토트랜지스터에 도달하는 빛이 달라지고, Collector 출력 Level이 변합니다.

실습 회로에서는 다음과 같이 연결했습니다.

- 적외선 LED: VDD - 220 Ω - Anode, Cathode - GND
- 포토트랜지스터: Collector - PC4 및 10 kΩ Pull-up, Emitter - GND

빛이 포토트랜지스터에 도달하면 Collector 전류가 흐르면서 PC4가 Low에 가까워지고, 빛이 차단되면 10 kΩ Pull-up에 의해 PC4가 High가 됩니다. 따라서 이 회로는 **빛 감지 시 Low, 차단 시 High**인 Active-Low 입력 구조입니다.

SG-207 자료에는 입력 LED의 Forward Current 최대 60 mA, IF = 30 mA에서 Forward Voltage Typical 1.2 V, 5 mm Gap 및 Rise/Fall Time Typical 5 μs가 제시되어 있습니다. 저항값과 전원 전압을 정할 때에는 LED 전류와 STM32 입력 전압을 함께 확인해야 합니다.

## 2. STM32CubeMX 설정

보관된 CubeMX Pinout에서 SG-207 출력이 연결된 PC4를 `GPIO_Input`으로 설정한 것을 확인했습니다.

| 대상 | STM32 Pin | 설정 |
|---|---|---|
| SG-207 Collector Output | PC4 | GPIO Input |

실습 회로에 외부 10 kΩ Pull-up이 있으므로 재현 시 PC4의 내부 Pull은 `No Pull`을 사용합니다. 다만 보관된 Pinout 화면에는 GPIO Pull-up/Pull-down 세부 설정이 표시되지 않아, 원본 CubeMX의 Pull 설정 자체는 확인 범위에서 제외했습니다.

PC4는 STM32F411xC/xE 자료에서 5 V Tolerant Digital I/O인 `FT`로 분류됩니다. 이 특성은 Digital GPIO Mode에 해당하며, PC4를 ADC Analog Mode로 사용할 때에는 동일하게 적용되지 않습니다.

## 3. GPIO Polling 코드

`data` 변수를 선언하고 Main Loop에서 PC4의 현재 입력 Level을 200 ms 간격으로 읽습니다.

```c
uint8_t data = 0;

while (1)
{
    data = HAL_GPIO_ReadPin(GPIOC, GPIO_PIN_4);
    HAL_Delay(200);
}
```

- `HAL_GPIO_ReadPin(GPIOC, GPIO_PIN_4)`: PC4의 현재 입력 값을 `GPIO_PIN_RESET` 또는 `GPIO_PIN_SET`으로 반환합니다.
- STM32F411의 GPIO Input은 `GPIOC_IDR`의 IDR4 Bit에 반영됩니다.
- `HAL_Delay(200)`: 디버거에서 값의 변화를 관찰하기 위한 Polling 간격이며 SG-207 자체의 응답 시간은 아닙니다.

## 4. 관찰 결과

Debugger의 Variables 창에서 `data`가 `0`과 `1`로 바뀌는 것을 확인했습니다. 보관된 두 화면에는 각 값에 대응하는 Slit의 물리 상태가 별도로 적혀 있지 않지만, 실습 회로 기준으로 다음과 같이 해석할 수 있습니다.

| Slit 상태 | 포토트랜지스터 | PC4 입력 | data |
|---|---|---|---|
| 빛 통과 | Conducting | Low | 0 |
| 빛 차단 | Off | Pull-up High | 1 |

## 5. 핵심 학습 포인트

- 투과형 포토인터럽터는 발광부와 수광부 사이의 빛 차단 여부를 전기적 출력 변화로 바꿉니다.
- 포토트랜지스터 Collector에 Pull-up 저항을 사용하면 빛 감지 상태가 Low로 나타나는 Active-Low 입력을 구성할 수 있습니다.
- `HAL_GPIO_ReadPin()`으로 읽는 값은 GPIO Pin에 형성된 현재 Logic Level이며, 내부적으로 `GPIOx_IDR`의 해당 Bit를 판독합니다.
- SG-207의 μs 단위 응답 시간과 200 ms Software Polling 간격은 서로 다른 개념입니다.
- 이번 실습은 PC4 Level Polling과 Debugger 관찰에 한정하며, GPIO EXTI 방식은 다음 학습 항목에서 별도로 다룹니다.

## 6. 검증 상태

- CubeMX PC4 `GPIO_Input`, `data` 변수, Polling 코드 및 Debugger의 0/1 관찰 화면을 원본 증거로 확인했습니다.
- CubeIDE 형식 `main.c`는 HAL Stub을 이용한 C 문법 및 경고 검사를 통과했습니다.
- SG-207 자료를 바탕으로 Pin 구성, 최대 정격, 전기·광학 특성 및 Active-Low 회로 동작을 검토했습니다.
- STM32F411 Reference Manual과 HAL/LL User Manual을 바탕으로 `GPIOx_IDR`와 `HAL_GPIO_ReadPin()`의 동작을 확인했습니다.
- STM32F411xC/xE 자료에서 PC4의 `FT` I/O 특성을 확인했습니다.
- 원본 `.ioc`와 전체 CubeIDE 프로젝트는 현재 보관본에 포함되지 않았습니다.
- 이번 정리 과정에서는 CubeIDE 재빌드와 STM32F411RE/SG-207 실물 재시험을 수행하지 않았습니다.

