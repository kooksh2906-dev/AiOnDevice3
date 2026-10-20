# UART - USART0 Polling Echo and Module

ATmega128A의 USART0를 비동기 UART 방식으로 설정하고, PC Serial Terminal에서 받은 1 byte를 다시 송신하는 Echo 실습입니다. Baud Rate 생성, 8N1 Frame, Polling 송수신, 문자열·16진수 출력 함수, 수신 오류 확인과 소스·헤더 모듈화를 단계적으로 학습합니다.

## 하드웨어 및 통신 전제

- MCU/System Clock: ATmega128A, 16 MHz
- Channel/Pin: USART0, `PE0/RXD0`, `PE1/TXD0`
- Serial 설정: 9600 bps, 8 Data bits, No Parity, 1 Stop bit(8N1)
- 동작 모드: Asynchronous Double Speed, `U2X0=1`
- Baud 설정: `UBRR0=207`, 실제 약 9615.38 bps, 오차 약 +0.16%(데이터시트 표의 반올림 표기 +0.2%)
- 송수신 방식: `RXC0`, `UDRE0` Flag를 확인하는 Blocking Polling
- Terminal 예시: `/dev/ttyUSB0`, 9600-8N1, Hardware/Software Flow Control 사용 안 함

USART0 주변장치를 활성화하면 RXD0와 TXD0의 일반 GPIO 동작이 주변장치에 의해 Override되므로 별도의 DDRE 방향 설정을 사용하지 않습니다. USB-UART 어댑터는 `MCU TXD0 -> Adapter RX`, `MCU RXD0 <- Adapter TX`, `GND <-> GND`로 교차 연결하며, RS-232 전압이 아닌 MCU와 호환되는 TTL Logic Level인지 확인해야 합니다.

## Baud Rate 계산

Double Speed 비동기 모드의 Baud Rate 식은 다음과 같습니다.

```text
BAUD = F_CPU / (8 * (UBRR0 + 1))
UBRR0 = F_CPU / (8 * BAUD) - 1
```

16 MHz와 9600 bps를 적용하면 계산값은 약 207.33이므로 `UBRR0=207`을 사용합니다.

```text
Actual BAUD = 16,000,000 / (8 * (207 + 1))
            = 9,615.38 bps
Error       = (9,615.38 / 9,600 - 1) * 100
            = 약 +0.16%
```

## 버전 구성

| 버전 | 코딩 스타일 | 핵심 학습 내용 |
|---|---|---|
| VER1: Original Polling Echo | 원자료 직접 레지스터 제어 | `RXC0` 수신 대기 후 `UDRE0` 송신 가능 상태를 확인하여 1 byte Echo |
| VER2: Improved Explicit 8N1 | 설정값·타입 명시 | `=` 기반 초기화, 8N1·UBRR 설정 순서, `uint8_t` 송수신 데이터 |
| VER3: Function & Data Practice | 함수·표현 변환 | 문자열 출력, 1 byte를 2자리 16진수와 Printable Character로 표시 |
| VER4: Error-Aware USART0 Module | 소스/헤더 분리 | Non-Blocking 확인 함수, FE0/DOR0/UPE0 상태 보존, Blocking Wrapper 제공 |

## 원형 코드 분석

1. `U2X0=1`로 비동기 Double Speed Mode를 선택합니다.
2. `RXEN0`, `TXEN0`을 설정해 USART0 Receiver와 Transmitter를 활성화합니다.
3. `UCSZ01:0=11`, `UCSZ02=0`으로 8-bit Character Size를 사용합니다.
4. Parity/Stop bit 관련 비트는 Reset 값 0에 의존하여 No Parity, 1 Stop bit가 됩니다.
5. `UBRR0H=0`, `UBRR0L=207`로 9600 bps를 구성합니다.
6. `RXC0`가 Set될 때까지 기다려 `UDR0`를 읽고, `UDRE0`가 Set되면 같은 byte를 `UDR0`에 써서 Echo합니다.

원형의 `|=` 초기화는 Reset 직후에는 의도대로 동작하지만 기존 Register 상태를 보존합니다. 특히 `UBRR0H |= 0`은 Register를 0으로 만드는 코드가 아니라 아무 변화도 주지 않는 연산입니다. VER1은 수업 원형을 보존하고, VER2 이후에는 필요한 전체 설정을 `=`로 명시합니다.

## 중요 수신 규칙

`FE0`, `DOR0`, `UPE0`는 Receive Buffer의 다음 Data와 함께 유효하며 `UDR0`를 읽으면 Buffer 상태가 바뀝니다. 따라서 오류가 필요한 경우 반드시 `UCSR0A`를 먼저 읽고 그다음 `UDR0`를 읽어야 합니다. VER4에서 이 순서를 적용합니다.

## 파일 구조

- `VER1_Original_Polling_Echo/main.c`
- `VER2_Improved_Explicit_8N1/main.c`
- `VER3_Function_Data_Practice/main.c`
- `VER4_Error_Aware_USART0_Module/main.c`
- `VER4_Error_Aware_USART0_Module/usart0.c`
- `VER4_Error_Aware_USART0_Module/usart0.h`
- `settings/register-hw-settings.md`
- `settings/baud-frame-settings.md`
- `LEARNING_ANALYSIS.md`

## 검증 범위

- 원자료의 Register 설정, Echo 흐름과 Terminal 9600-8N1 설정을 확인했습니다.
- ATmega128A의 USART0 Pin, Register bit, Double Speed Baud 식, Receive Buffer와 Error Flag 읽기 순서를 반영했습니다.
- 5개 C 소스의 호스트 C 문법 검사를 경고 없이 완료했습니다.
- AVR-GCC 빌드, USB-UART Logic Level 확인과 실물 보드 Loopback 검증은 수행하지 않았습니다.
