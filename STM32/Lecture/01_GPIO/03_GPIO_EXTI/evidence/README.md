# 원본 Evidence 목록

다음 이미지는 보관된 `LAB_EXTI` 학습 기록에서 확인한 원본 화면입니다.

| 파일 | 내용 |
|---|---|
| `01_mcu_pinout.png` | STM32F411RE Pinout: PC13 GPIO_EXTI13, PA5 GPIO_Output |
| `02_gpio_exti_configuration.png` | PC13 Rising Edge Trigger 및 Pull-up 설정 |
| `03_nvic_configuration.png` | EXTI line[15:10] Interrupt Enable 및 Priority 0 |
| `04_original_callback.png` | `HAL_GPIO_EXTI_Callback()`에서 PA5 Toggle |

이미지에 나타나지 않은 전체 `main.c`, `gpio.c`, `stm32f4xx_it.c` 및 `.ioc` 내용은 원본으로 단정하지 않습니다. 생성 코드의 일반적인 연결 부분은 별도의 복원본에서 명시적으로 구분했습니다.
