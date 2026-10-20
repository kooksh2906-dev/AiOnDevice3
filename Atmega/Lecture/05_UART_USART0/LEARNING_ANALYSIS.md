# UART 학습 분석

## 1. 학습 흐름

1. Serial Frame을 구성하는 Start, Data, Parity, Stop bit의 역할을 구분합니다.
2. System Clock, U2X, UBRR 값으로 실제 Baud Rate를 계산합니다.
3. RXC0와 UDRE0 Flag를 Polling하여 Receive/Transmit Buffer 접근 시점을 판단합니다.
4. UDR0 하나가 Read 시 Receive Buffer, Write 시 Transmit Buffer로 동작함을 이해합니다.
5. 1 byte Echo에서 문자열·16진수 출력 함수로 확장합니다.
6. Status를 먼저 읽고 Data를 읽는 순서로 Frame/Overrun/Parity Error를 보존합니다.
7. 직접 Register 제어를 재사용 가능한 USART0 소스·헤더 모듈로 정리합니다.

## 2. 원본에서 확인한 핵심

- 원본은 16 MHz, U2X=1, UBRR0=207 조합의 9600 bps Echo입니다.
- `while (!(UCSR0A & (1 << RXC0)))`는 unread data가 도착할 때까지 Blocking합니다.
- `while (!(UCSR0A & (1 << UDRE0)))`는 UDR0 Transmit Buffer가 비워질 때까지 Blocking합니다.
- 수신 byte를 즉시 송신하므로 PC Terminal에서 입력과 수신 결과를 비교할 수 있습니다.

## 3. 개선 판단

- `|=`는 이전 설정을 남기므로 독립적인 초기화 함수에서는 `=`를 사용해 의도를 명확히 합니다.
- `UBRR0H |= 0`은 Clear가 아니므로 High/Low byte를 계산값으로 직접 대입합니다.
- `unsigned` 대신 실제 UDR0 폭과 같은 `uint8_t`를 사용합니다.
- 설정 중 송수신을 막기 위해 UCSR0B를 먼저 0으로 만들고 Baud/Frame 설정 후 RX/TX를 활성화합니다.
- 오류 진단이 필요한 버전에서는 UCSR0A를 UDR0보다 먼저 읽습니다.

## 4. 이력서에 연결할 수 있는 학습 성과

- 데이터시트의 Baud Rate 식과 Register bit 조합을 실제 통신 설정으로 변환
- Buffer Ready Flag 기반의 Blocking Polling 송수신 흐름 구현
- Serial Terminal을 이용한 byte 단위 Loopback 검증 구조 이해
- Frame Error, Data Overrun, Parity Error의 발생 위치와 확인 순서 분석
- 단일 함수 실습에서 명시적 초기화와 재사용 가능한 통신 모듈로 코드 구조 개선

## 5. 과장하지 않아야 할 범위

- 원자료는 Polling Echo이며 Interrupt, Ring Buffer, DMA 방식이 아닙니다.
- Terminal Echo 성공 화면은 byte 송수신 결과이며 장시간 Error Rate나 최대 Throughput 검증은 아닙니다.
- RS-232 Transceiver나 USB-UART 전기적 Level 변환 회로 설계 실습으로 설명하지 않습니다.
