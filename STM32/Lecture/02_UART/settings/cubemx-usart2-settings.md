# STM32CubeMX USART2 설정

## 공통 UART 설정

| 항목 | 학습 기준 |
|---|---|
| Peripheral | USART2 |
| Mode | Asynchronous |
| Terminal 설정 | 9600 bps, 8 Data Bits, No Parity, 1 Stop Bit |
| Hardware Flow Control | 사용하지 않음 |
| Debug Terminal | moserial 또는 Tera Term |

Terminal의 Baud Rate와 CubeMX/`usart.c`에서 생성된 Baud Rate는 동일해야 합니다. NUCLEO-F411RE에서 USART2를 ST-LINK Virtual COM Port로 사용할 때는 Board 연결에 맞는 TX/RX Alternate Function Pin을 사용합니다.

## Polling

- USART2 Asynchronous Mode와 TX/RX Pin을 설정합니다.
- UART Global Interrupt와 DMA는 Polling 자체에는 필요하지 않습니다.
- `HAL_UART_Transmit()`과 `HAL_UART_Receive()`의 `Timeout` 동안 호출한 실행 흐름이 대기할 수 있습니다.

## Interrupt

원본 CubeMX 화면에서 다음 설정을 확인했습니다.

| 항목 | 원본 설정 |
|---|---|
| USART2 global interrupt | Enabled |
| Preemption Priority | 0 |
| Sub Priority | 0 |

`USART2_IRQHandler()`가 HAL UART IRQ Handler를 호출하고, 지정한 수신 길이가 완료되면 `HAL_UART_RxCpltCallback()`이 실행됩니다. 수신을 계속하려면 Callback 또는 Main Context에서 `HAL_UART_Receive_IT()`을 다시 호출해야 합니다.

Priority 숫자가 작을수록 우선순위가 높습니다. FreeRTOS에서 ISR이 RTOS API를 사용하는 경우에는 CubeMX 기본값을 그대로 적용하지 말고 `configLIBRARY_MAX_SYSCALL_INTERRUPT_PRIORITY`와 함께 검토해야 합니다.

## DMA RX

원본 CubeMX 화면에서 다음 설정을 확인했습니다.

| 항목 | 원본 설정 또는 문서 확인값 |
|---|---|
| DMA Request | USART2_RX |
| DMA Controller | DMA1 |
| Stream | Stream 5 |
| Channel | Channel 4 |
| Direction | Peripheral to Memory |
| Priority | Low |

- STM32F411xC/E의 DMA1 Request Mapping에서 USART2_RX는 Stream 5, Channel 4에 연결됩니다.
- 생성 코드에서는 `MX_DMA_Init()` 후 `MX_USART2_UART_Init()` 순서로 초기화합니다.
- HAL DMA Handle을 UART RX Handle과 연결하고 DMA Stream IRQ를 NVIC에서 활성화해야 합니다.
- 원본 화면에 표시되지 않은 Data Width, Memory Increment 및 Mode 값은 이번 원본 설정값으로 단정하지 않습니다.

## 실행 관찰 시 주의점

- Debug Mode에서 Program을 Resume한 뒤 Terminal에서 데이터를 전송합니다.
- Live Expressions에 `rxData`를 등록하면 Buffer 변화를 관찰할 수 있습니다.
- ST-LINK의 COM LED는 PC와 ST-LINK 사이의 USB/Debug/Virtual COM 통신 상태를 나타내며, 사용자 PA5 LED와 역할이 다릅니다.
