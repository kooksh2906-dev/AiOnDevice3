# 03. I2C

STM32F411RE의 I2C1과 PCF8574 I/O Expander를 이용하여 HD44780 호환 16x2 Character LCD를 제어한 학습 기록입니다. 수업 자료에 남은 I2C 개념·CubeMX 설정·Driver 코드·`main.c` 화면을 기준으로 실습 흐름을 복원하고, 통신 오류를 상위 코드에서 판단할 수 있도록 보완한 개선본을 별도 버전으로 구분했습니다.

## 1. 실제 학습 범위

- I2C의 SDA·SCL 두 신호선과 START·STOP Condition을 확인했습니다.
- 7-bit Slave Address와 HAL API에 전달하는 Shifted Address의 차이를 학습했습니다.
- STM32F411RE의 I2C1을 Standard Mode 100 kHz로 설정했습니다.
- PB6을 I2C1_SCL, PB7을 I2C1_SDA로 사용했습니다.
- PCF8574의 8-bit 출력으로 LCD의 RS, E, Backlight 및 DB4-DB7을 제어했습니다.
- HD44780 Command/Data를 상위·하위 Nibble로 나누어 4-bit 방식으로 전송했습니다.
- LCD 두 행에 `Hello ARM`, `Good Morning`을 출력했습니다.
- 후속 응용 주제로 초음파 거리값을 문자열로 변환하여 LCD에 표시하는 흐름을 다뤘습니다. 실제 거리 측정 코드는 이후 HC-SR04 항목과 연결하여 정리합니다.

## 2. I2C Protocol

I2C는 SDA와 SCL을 공유하는 동기식 직렬 Bus입니다. 두 선은 Open-drain 방식으로 동작하므로 장치가 High를 직접 출력하지 않고, Low로 당기거나 선을 해제합니다. 따라서 SDA와 SCL에는 Pull-up이 필요합니다.

### 신호 변화 규칙

- 일반 Data Bit는 **SCL이 Low일 때 SDA를 변경**하고 SCL이 High인 동안 안정적으로 유지합니다.
- SCL이 High인 상태에서 SDA가 High에서 Low로 바뀌면 START Condition입니다.
- SCL이 High인 상태에서 SDA가 Low에서 High로 바뀌면 STOP Condition입니다.
- Byte는 MSB부터 전송하며, 8 Data Bit 뒤의 9번째 Clock에서 Receiver가 ACK 또는 NACK를 응답합니다.
- Bus를 해제하지 않고 방향이나 대상 전송을 이어갈 때 Repeated START를 사용할 수 있습니다.

### Address와 ACK

수업에 사용한 Backpack의 7-bit Address는 `0x27`입니다. STM32 HAL의 `HAL_I2C_Master_Transmit()`에 전달하는 `DevAddress`는 7-bit Address를 한 Bit 왼쪽으로 이동한 값이므로 `(0x27U << 1)`, 즉 `0x4E`를 사용합니다.

PCF8574의 Address Bit는 `0100 A2 A1 A0`으로 구성됩니다. 수업 자료의 Address 표에서 A2-A0가 모두 High이면 7-bit Address는 `0x27`, 8-bit Write Address는 `0x4E`, Read Address는 `0x4F`가 됩니다. 실제 Backpack은 PCF8574A 또는 다른 A2-A0 Strap을 사용할 수 있으므로 Module의 Chip Marking과 Address Scan 결과를 우선해야 합니다.

### Arbitration과 Clock Stretching

- 여러 Controller가 동시에 START를 만들 수 있는 Multi-controller 환경에서는 SDA를 High로 내보내려던 Controller가 실제 Low를 읽으면 Arbitration에서 패배한 것으로 판단합니다.
- Target은 처리가 끝날 때까지 SCL을 Low로 유지하여 Clock Stretching을 요청할 수 있습니다.
- 이번 실습은 하나의 STM32 Controller와 하나의 LCD Backpack을 사용한 단일 Controller 구성입니다.

## 3. PCF8574와 HD44780 연결

수업 코드의 출력 Byte는 다음 Bit Mapping을 전제로 합니다.

| PCF8574 Bit | LCD 신호 | 코드 값 | 역할 |
|---|---|---:|---|
| P7-P4 | DB7-DB4 | `data & 0xF0` | 4-bit LCD Data Nibble |
| P3 | Backlight | `0x08` | Backlight ON |
| P2 | E | `0x04` | High-to-Low Enable Pulse |
| P1 | R/W | `0x00` | Write-only |
| P0 | RS | `0x01` | 0: Command, 1: Character Data |

한 Byte를 보낼 때 상위 Nibble의 E High/Low와 하위 Nibble의 E High/Low를 연속 전송하므로 `i2c_buffer[4]`를 사용합니다.

```c
i2c_buffer[0] = high_nibble | 0x04 | 0x08;
i2c_buffer[1] = high_nibble | 0x00 | 0x08;
i2c_buffer[2] = low_nibble  | 0x04 | 0x08;
i2c_buffer[3] = low_nibble  | 0x00 | 0x08;
```

Data 전송에서는 P0의 RS Bit를 추가하여 `0x05`와 `0x01`을 사용합니다. 이 Mapping은 수업에 사용한 Backpack 기준이며, 다른 Module은 PCF8574와 LCD Pin 연결이 다를 수 있습니다.

## 4. 버전 구성

| 버전 | 성격 | 내용 |
|---|---|---|
| `VER1_Reconstructed_Lecture_Code` | 수업 화면 기반 복원본 | 원본 함수명과 흐름을 보존합니다. I2C 전송이 성공할 때까지 반복하므로 장치 미응답 시 해당 함수에 머무를 수 있습니다. |
| `VER2_Improved_Status_Checked` | 별도 개선본 | 7-bit/HAL Address를 분리하고, `HAL_I2C_IsDeviceReady()`, 전송 결과 반환, 문자열 중단, Row·Column 범위 검사를 추가합니다. |

두 버전의 `main.c`는 CubeIDE 생성 형식을 유지합니다. 사용자 Header는 `USER CODE Includes`, 초기 LCD 호출은 `USER CODE BEGIN 2`에 배치했습니다. `MX_I2C1_Init()`과 `MX_USART2_UART_Init()`은 CubeMX 생성 초기화 호출이므로 USER CODE 영역 밖에 유지했습니다.

## 5. HAL API와 STM32F411 I2C Register

| 계층 | 주요 항목 | 역할 |
|---|---|---|
| Application | `i2c_lcd_init()`, `lcd_command()`, `lcd_data()` | LCD Command/Data와 초기화 순서를 구성합니다. |
| HAL | `HAL_I2C_Master_Transmit()` | START, Address, Data, ACK 확인 및 STOP을 포함한 Blocking 송신을 수행합니다. |
| HAL | `HAL_I2C_IsDeviceReady()` | 지정 Address에서 Target이 ACK하는지 제한된 횟수만큼 확인합니다. |
| Register | `I2C_CR1` | Peripheral Enable, START, STOP, ACK 등을 제어합니다. |
| Register | `I2C_CR2` | APB Clock 정보와 Interrupt/DMA 관련 Bit를 포함합니다. |
| Register | `I2C_DR` | 송수신 Data Register입니다. |
| Register | `I2C_SR1` | SB, ADDR, BTF, RXNE, TXE 및 Error Flag를 제공합니다. |
| Register | `I2C_SR2` | BUSY, MSL, TRA 등 Bus와 동작 상태를 제공합니다. |
| Register | `I2C_CCR`, `I2C_TRISE` | SCL 주기와 Rise Time 조건을 설정합니다. |
| Register | `I2C_FLTR` | Analog/Digital Noise Filter를 설정합니다. |

STM32F411 I2C는 Standard Mode 100 kHz와 Fast Mode 400 kHz를 지원합니다. 이번 실습은 CubeMX 화면에 확인되는 Standard Mode 100 kHz를 사용합니다.

## 6. I2C·SPI·Ethernet 비교

| 구분 | I2C | SPI | Ethernet |
|---|---|---|---|
| 주된 범위 | Board 내부 저속 Peripheral Bus | Board 내부 고속 Peripheral 연결 | 장치·Network 간 Frame 통신 |
| 기본 신호 | SDA, SCL | SCLK, MOSI, MISO, NSS/CS | MAC-PHY Interface와 차동 Pair |
| Clock | Controller가 SCL 생성 | Controller가 SCLK 생성 | PHY가 Link Clock을 복구·사용 |
| Duplex | 일반적으로 Half-duplex 성격 | Full-duplex 가능 | 현대 Switched Link는 Full-duplex |
| 장치 선택 | Address | 개별 Chip Select | MAC Address와 상위 Protocol 주소 |
| 응답·오류 단서 | ACK/NACK, Arbitration, Error Flag | 표준 ACK 없음, 장치별 Protocol에 의존 | FCS, Link 계층 및 상위 Protocol에서 처리 |
| 전기적 특징 | Open-drain + Pull-up | 주로 Push-pull | Transformer/PHY와 Differential Signaling |
| 장점 | 두 선으로 여러 장치 연결 | 높은 속도와 낮은 Protocol Overhead | 장거리·다중 Node·표준 Network Stack |
| 주의점 | Address 충돌, Pull-up, Bus Capacitance | CS Pin 증가, CPOL/CPHA 일치 | MAC·PHY·TCP/IP Stack 등 복잡도 증가 |
| 이번 학습 상태 | 실제 I2C LCD 실습 | 비교 이론 | 비교 이론, STM32F411RE에는 Ethernet MAC 없음 |

SPI와 Ethernet은 이번 항목에서 실습했다고 주장하지 않습니다. I2C와 혼동하기 쉬운 차이를 면접에서 설명할 수 있도록 비교한 이론 항목입니다.

## 7. 신입 면접 예상 질문

### I2C에 Pull-up 저항이 필요한 이유는 무엇입니까?

SDA와 SCL이 Open-drain 방식이어서 장치는 선을 Low로만 구동하고 High는 선을 해제하기 때문입니다. 해제된 선을 High로 복귀시키기 위해 Pull-up이 필요합니다.

### 7-bit 주소 `0x27`을 HAL에 왜 `0x4E`로 전달합니까?

STM32 HAL I2C API의 `DevAddress`는 7-bit Address를 한 Bit 왼쪽으로 이동한 형식을 요구하기 때문입니다. 최하위 Bit 위치는 전송 방향 Bit에 해당하므로 `(0x27U << 1)`을 전달합니다.

### ACK와 NACK의 차이는 무엇입니까?

8 Bit 전송 뒤 9번째 Clock에서 Receiver가 SDA를 Low로 만들면 ACK입니다. SDA가 High로 유지되면 NACK이며, 주소 불일치·수신 종료·장치 미응답 등을 판단하는 단서가 됩니다.

### I2C와 SPI 중 무엇을 선택하시겠습니까?

필요 속도, Pin 수, 장치 수, Duplex 여부와 대상 IC의 Interface를 기준으로 선택합니다. 여러 저속 장치를 적은 Pin으로 연결하면 I2C가 유리하고, 높은 전송률과 낮은 Overhead가 중요하면 SPI가 유리합니다.

### Ethernet을 I2C나 SPI와 같은 방식으로 비교하면 안 되는 이유는 무엇입니까?

I2C와 SPI는 주로 Board 내부 Peripheral Bus인 반면 Ethernet은 MAC Frame, PHY, Switching 및 IP/TCP/UDP 같은 상위 계층과 결합되는 Network 기술이기 때문입니다. 신호선 수나 Clock만 비교하기보다 적용 범위와 계층을 먼저 구분해야 합니다.

## 8. 핵심 학습 포인트

- START와 STOP은 SCL이 High일 때의 SDA 변화라는 예외 규칙으로 구분합니다.
- 7-bit Slave Address와 Read/Write Bit를 포함한 8-bit 전송 값을 구분합니다.
- HAL API의 Address 인자 규칙을 Datasheet의 표기 방식과 연결할 수 있습니다.
- PCF8574는 I2C 직렬 Data를 8-bit 병렬 출력으로 바꾸어 LCD의 4-bit Interface를 제어합니다.
- 하나의 LCD Byte를 두 Nibble과 두 번의 E Pulse로 변환하는 Driver 흐름을 이해합니다.
- Blocking HAL API의 Timeout과 재시도 정책은 Driver가 멈추는 범위를 결정합니다.
- SPI는 별도 Address/ACK가 없는 고속 Peripheral Interface이고, Ethernet은 적용 계층과 시스템 규모가 다른 Network 기술입니다.

## 9. 검증 범위

- 2026년 5월 21일 I2C LCD 학습 메일의 개념, CubeMX 설정 및 코드 화면을 대조했습니다.
- STM32F411 Reference Manual, STM32F4 HAL/LL User Manual, PCF8574 및 HD44780 자료를 기준으로 정적 검토했습니다.
- GitHub에는 코드와 설정 설명만 보존하며 원본 화면 캡처는 Notion에 배치합니다.
- 두 버전의 CubeIDE 형식 `main.c`와 LCD Driver Source는 HAL Stub을 사용하여 C 문법 및 경고 검사를 수행합니다.
- 원본 `.ioc`와 전체 CubeIDE Project는 현재 보관본에 포함되지 않았습니다.
- 이번 정리 과정에서는 CubeIDE 재빌드와 STM32F411RE/I2C LCD 실물 재시험을 수행하지 않았습니다.
