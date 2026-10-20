# USART0 Register 및 Hardware Setting

## 1. Pin 연결

| ATmega128A Pin | USART0 기능 | 연결 |
|---|---|---|
| PE0 | RXD0, Receive Data Input | USB-UART Adapter TX |
| PE1 | TXD0, Transmit Data Output | USB-UART Adapter RX |
| GND | 공통 기준 전위 | USB-UART Adapter GND |

- TX와 RX는 서로 교차 연결합니다.
- USB-UART Adapter는 MCU I/O 전압과 호환되는 TTL Logic Level이어야 합니다.
- 일반 RS-232의 양·음 전압 신호를 MCU Pin에 직접 연결하지 않습니다.
- RXD0 Receiver와 TXD0 Transmitter가 활성화되면 해당 Pin의 일반 Port 동작은 USART0가 Override합니다.

## 2. 주요 Register

| Register | 주소 | 실습에서 사용하는 기능 |
|---|---:|---|
| UDR0 | I/O `$0C`, Data `$2C` | Read: Receive Data, Write: Transmit Data |
| UCSR0A | I/O `$0B`, Data `$2B` | RXC0, UDRE0, FE0, DOR0, UPE0, U2X0 |
| UCSR0B | I/O `$0A`, Data `$2A` | RXEN0, TXEN0, UCSZ02 및 Interrupt Enable |
| UCSR0C | Data `$95` | 비동기/동기, Parity, Stop bit, Character Size |
| UBRR0L | I/O `$09`, Data `$29` | Baud Rate 값 하위 8 bit |
| UBRR0H | Data `$90` | Baud Rate 값 상위 4 bit |

## 3. UCSR0A

| Bit | 이름 | 의미 |
|---:|---|---|
| 7 | RXC0 | Receive Buffer에 읽지 않은 Data가 존재 |
| 6 | TXC0 | 전체 Frame 송신 완료, 1을 써서 Clear 가능 |
| 5 | UDRE0 | Transmit Buffer가 비어 UDR0 Write 가능 |
| 4 | FE0 | 첫 Stop bit가 0인 Frame Error |
| 3 | DOR0 | Receive Buffer 처리 지연에 따른 Data Overrun |
| 2 | UPE0 | Parity 검사 불일치 |
| 1 | U2X0 | 비동기 통신 Baud Divider를 16에서 8로 변경 |
| 0 | MPCM0 | Multi-processor Communication Mode |

## 4. UCSR0B와 UCSR0C

- `RXEN0=1`: Receiver Enable
- `TXEN0=1`: Transmitter Enable
- `UCSZ02:0=011`: 8-bit Character
- `UMSEL0=0`: Asynchronous Mode
- `UPM01:0=00`: Parity Disabled
- `USBS0=0`: 1 Stop bit
- `UCPOL0=0`: Asynchronous Mode에서 0으로 설정

## 5. UDR0 접근 순서

### 송신

1. UDRE0가 1인지 확인합니다.
2. UDR0에 Data를 씁니다.
3. USART0가 Transmit Shift Register를 통해 TXD0로 Serial Frame을 출력합니다.

### 수신

1. RXC0가 1인지 확인합니다.
2. 오류 정보가 필요하면 UCSR0A를 먼저 읽습니다.
3. UDR0를 한 번 읽어 Data를 꺼냅니다.

Receive Buffer는 2-level FIFO이므로 각 수신 Character마다 UDR0를 한 번만 읽습니다.

## 6. 호환 모드 전제

ATmega103 Compatibility Mode에서는 USART1, UBRR0H와 UCSR0C를 사용할 수 없고 USART0의 Asynchronous Operation만 지원합니다. 본 코드는 UCSR0C와 UBRR0H를 명시적으로 사용하므로 일반 ATmega128A Mode를 전제로 합니다.
