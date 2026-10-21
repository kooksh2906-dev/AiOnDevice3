# 02. UART

STM32F411RE의 USART2를 이용하여 UART 송수신을 Polling, Interrupt 및 DMA 방식으로 처리한 학습 기록입니다.

동일한 UART 데이터 전송이라도 CPU가 완료 시점까지 기다리는지, 주변장치 Interrupt에 응답하는지, DMA Controller에 메모리 전송을 맡기는지에 따라 Main Loop의 실행 가능 시간과 구현 구조가 달라집니다. 이 항목에서는 실제 수업 코드와 설정 화면을 기준으로 세 방식을 비교하고, 원본에서 확인되지 않는 부분은 `Reconstructed`로 구분합니다.

## 실제 학습 기록의 범위

- Polling 송신: `HAL_UART_Transmit()`으로 문자열을 1초마다 전송
- Polling 수신: `HAL_UART_Receive()`이 4바이트 수신 또는 Timeout까지 실행 흐름을 점유하는 현상 관찰
- Interrupt 수신: `HAL_UART_Receive_IT()`으로 수신을 예약하고 `HAL_UART_RxCpltCallback()`에서 재등록
- UART 구분: Callback 인자 `huart->Instance`로 USART2에서 발생한 완료 Event인지 확인
- DMA 수신: CubeMX에서 `USART2_RX`, `DMA1 Stream 5`, Peripheral-to-Memory를 설정하고 `HAL_UART_Receive_DMA()`로 전환한 흔적 확인

DMA는 설정 화면과 API 전환 흔적은 남아 있지만 완성된 실행 코드와 동작 결과가 확인되지 않습니다. 따라서 원본 흔적과 고정 길이 DMA 수신 복원 예제를 별도 버전으로 보존합니다.

## 입출력 방식 비교

| 방식 | 대표 HAL API | CPU 동작 | 완료 확인 | 실제 자료 상태 |
|---|---|---|---|---|
| Polling | `HAL_UART_Transmit()`, `HAL_UART_Receive()` | 전송·수신 완료 또는 Timeout까지 호출부에서 대기 | 함수 반환값 | 송신 코드와 수신 비교 코드 확인 |
| Interrupt | `HAL_UART_Transmit_IT()`, `HAL_UART_Receive_IT()` | API 호출 후 Main 흐름으로 복귀 | `HAL_UART_TxCpltCallback()`, `HAL_UART_RxCpltCallback()` | 4바이트 수신 및 1바이트 Echo 코드 확인 |
| DMA | `HAL_UART_Transmit_DMA()`, `HAL_UART_Receive_DMA()` | UART와 Memory 사이 전송을 DMA가 수행 | Half/Complete Callback | RX 설정과 API 흔적 확인, 동작 완성본 미확인 |

## 폴더 구성

### `01_Polling`

- `VER1_Original_Blocking_Transmit`: `hello stm!!` 문자열을 주기적으로 전송한 원본 흐름
- `VER2_Reconstructed_Blocking_Receive_LED`: 4바이트 Polling 수신과 PA5 LED 점멸을 함께 배치한 비교용 복원본

Polling 수신은 정확히는 영구 정지가 아니라 **지정한 4바이트를 모두 받거나 Timeout이 발생할 때까지** 호출부를 Blocking합니다. 따라서 입력이 없으면 LED Toggle 주기가 Timeout만큼 늦어집니다.

### `02_Interrupt`

- `VER1_Original_4Byte_Rearm`: 4바이트 수신 완료 후 같은 Buffer로 Interrupt 수신을 다시 등록
- `VER2_Original_Instance_Filtered_Echo`: USART2를 확인하고 1바이트를 Echo한 원본 흐름
- `VER3_Improved_Deferred_Echo`: Callback에서는 Event만 기록하고 Echo와 다음 수신 등록은 Main Context에서 처리

원본 Echo는 `HAL_UART_Transmit()`을 Callback 안에서 호출하므로 Interrupt Context가 송신 완료 또는 Timeout까지 점유될 수 있습니다. 개선본은 이 Blocking 송신을 Main Context로 옮깁니다. 개선본은 사람이 한 글자씩 입력하는 학습 예제에 맞춘 구조이며, 연속 고속 수신에는 Ring Buffer나 DMA Circular/Receive-to-Idle 구조가 필요합니다.

### `03_DMA`

- `VER1_Original_API_Trace`: 원본에 주석으로 남은 `HAL_UART_Receive_DMA()` 전환 흔적
- `VER2_Reconstructed_Fixed_Length_RX`: 4바이트 DMA 수신 완료 Event를 Main Context에서 처리하고 다시 수신을 시작하는 복원 예제

DMA 수신은 USART의 `RXNE` Event에 따라 `USART_DR`의 데이터를 SRAM Buffer로 옮깁니다. STM32F411xC/E의 USART2_RX는 원본 CubeMX 화면과 Reference Manual의 Mapping에 따라 `DMA1 Stream 5, Channel 4`를 사용할 수 있습니다.

## HAL과 레지스터의 연결

- `HAL_UART_Receive()`: `RXNE` 등 수신 상태를 확인하며 지정 길이 또는 Timeout까지 Blocking
- `HAL_UART_Receive_IT()`: `RXNEIE` 등 수신 Interrupt를 사용하고 완료 시 `HAL_UART_RxCpltCallback()` 호출
- `HAL_UART_Receive_DMA()`: `USART_CR3.DMAR`와 DMA Stream을 이용해 `USART_DR`에서 Memory로 전송
- `USART_SR.RXNE`: 수신 Shift Register의 데이터가 Data Register로 이동하여 읽을 준비가 되었음을 표시
- `USART_DR`: 수신 데이터 Read 및 송신 데이터 Write에 사용하는 Data Register

## 핵심 학습 포인트

- Polling, Interrupt 및 DMA는 UART Protocol 자체가 아니라 CPU가 송수신 완료를 처리하는 방식의 차이입니다.
- 고정 길이 수신 API에서 `Size`는 수신 완료 Callback이 호출되는 기준입니다.
- Interrupt/DMA API는 최초 한 번 호출하는 것으로 끝나지 않으며, 연속 수신을 위해 적절한 시점에 다시 등록해야 합니다.
- 여러 UART가 같은 HAL Callback을 공유할 수 있으므로 `huart->Instance`를 확인해야 합니다.
- Callback 안에서는 긴 Blocking 처리보다 Event 기록과 상태 갱신만 수행하는 편이 안전합니다.
- DMA는 CPU 개입을 줄이지만 Stream/Channel, Direction, Memory 주소, 전송 길이 및 IRQ 설정을 함께 이해해야 합니다.
- 문자열 전송에서 `sizeof(array)`는 문자열 끝의 `\0`까지 포함합니다. Terminal에 Null 문자를 보낼 필요가 없다면 `sizeof(array) - 1U` 또는 실제 문자열 길이를 사용합니다.

## 검증 범위

- 수업 코드, CubeMX 화면, STM32F411 Reference Manual 및 STM32F4 HAL/LL User Manual을 기준으로 정적 검토했습니다.
- 코드 조각은 HAL Stub을 사용한 C 문법 검사를 수행합니다.
- 원본 `.ioc`와 전체 CubeIDE Project는 확인되지 않았으며, CubeIDE 재빌드와 실물 보드 재시험은 수행하지 않았습니다.
