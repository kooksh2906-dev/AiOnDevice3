# 03. Character LCD

STM32F411RE의 GPIO를 이용하여 HD44780 호환 16x2 Character LCD를 병렬 방식으로 제어한 학습 기록입니다. 2026년 5월 20일의 8-bit 실습과 5월 21일의 4-bit 실습을 실제 학습 순서대로 보존했습니다.

이번 항목은 GPIO 병렬 제어만 다룹니다. I2C Backpack을 사용하는 Character LCD 실습은 I2C 항목에서 별도로 정리합니다.

## 1. 학습 범위

- RS로 Instruction Register와 Data Register를 선택합니다.
- R/W를 GND에 연결하여 Write-only 방식으로 사용합니다.
- E Pin에 High-to-Low Pulse를 만들어 Command 또는 Data를 LCD에 전달합니다.
- 8-bit 방식은 DB0-DB7을 한 번에 출력합니다.
- 4-bit 방식은 DB7-DB4에 상위 Nibble과 하위 Nibble을 차례로 출력합니다.
- DDRAM Address와 0x80을 OR 연산하여 Cursor 위치를 지정합니다.

## 2. 버전 구성

| 버전 | 성격 | 내용 |
|---|---|---|
| VER1_Original_8Bit_Parallel | 실제 실습 원본 복원 | RS, E 및 DB0-DB7의 10개 GPIO를 사용합니다. |
| VER2_Original_4Bit_Parallel | 4-bit 병렬 제어 | RS, E 및 DB4-DB7의 6개 GPIO를 사용하며, 초기화 Nibble을 LCD_Data4Bit()의 입력 형식에 맞춰 전달합니다. |

## 3. GPIO 및 배선

세부 Pin Mapping과 CubeMX 설정은 settings/cubemx-gpio-settings.md에 정리했습니다.

- VSS: GND
- VDD: +5 V
- V0(VEE): 가변저항으로 Contrast 조절
- R/W: GND 고정
- A(LED+): +5 V
- K(LED-): GND

LCD Logic 전원과 Backlight 전원은 사용한 Module 사양을 기준으로 연결해야 하며, STM32 GPIO 입력 허용 전압과 혼동하지 않아야 합니다. 이번 실습은 R/W를 GND에 연결한 Write-only 구성이라 LCD에서 STM32 방향으로 Data Bus를 구동하지 않습니다.

## 4. Command와 Data 전달

HAL_GPIO_WritePin()으로 Data Bus와 제어 Pin을 출력한 뒤 E Pin에 Pulse를 인가합니다.

    HAL_GPIO_WritePin(LCD_RS_GPIO, LCD_RS_PIN, GPIO_PIN_RESET);
    LCD_Data(commandData);
    LCD_EnablePin();

- RS = 0: Command 전달
- RS = 1: Character Data 전달
- E High -> Low: 설정한 Data를 LCD가 받아들이는 시점

STM32 HAL의 HAL_GPIO_WritePin()은 GPIOx_BSRR를 사용하여 대상 Pin을 Set 또는 Reset합니다. LCD 실습에서는 여러 Port에 흩어진 Data Pin을 개별 호출하므로 모든 Data Bit가 완전히 동시에 바뀌는 구조는 아니지만, E Pulse 전에 Data를 모두 설정하므로 LCD가 유효 Data를 받아들이도록 순서를 구성했습니다.

## 5. 8-bit 방식

8개의 Data Pin을 한 번에 설정한 뒤 E Pulse를 한 번 발생시킵니다.

    HAL_GPIO_WritePin(LCD_D0_GPIO, LCD_D0_PIN,
                      (data & 0x01U) ? GPIO_PIN_SET : GPIO_PIN_RESET);
    /* DB1-DB7도 같은 방식으로 설정 */
    LCD_EnablePin();

GPIO 사용량은 많지만 한 Byte를 한 번의 Enable Cycle로 전달하므로 데이터 흐름을 직관적으로 확인할 수 있습니다.

## 6. 4-bit 방식

상위 Nibble을 먼저 전달한 뒤 하위 Nibble을 DB7-DB4 위치로 이동하여 전달합니다.

    LCD_Data4Bit(data & 0xF0U);
    LCD_EnablePin();

    LCD_Data4Bit((uint8_t)((data << 4) & 0xF0U));
    LCD_EnablePin();

GPIO 사용량은 줄지만 한 Byte마다 두 번의 Enable Cycle이 필요합니다.

## 7. 4-bit 초기화

전원 인가 후 충분히 대기한 다음 DB7-DB4에 `0011`을 세 번 전달하고, `0010`을 전달하여 4-bit Interface로 전환합니다. `LCD_Data4Bit()`는 Byte의 상위 Nibble 위치를 검사하므로 각각 `0x30U`, `0x20U`로 전달합니다.

    LCD_Data4Bit(0x30U);
    LCD_EnablePin();
    /* 동일한 0x30U 전달을 두 차례 더 수행 */
    LCD_Data4Bit(0x20U);
    LCD_EnablePin();

이후 `0x28U`로 4-bit·2-line·5x8 Font를 설정하고, `0x0CU`로 Display ON·Cursor OFF·Blink OFF, `0x01U`로 Display Clear, `0x06U`으로 Cursor Increment·No Shift를 설정합니다. R/W를 GND에 고정한 구성에서는 Busy Flag를 읽을 수 없으므로 각 단계의 실행 시간을 Software Delay로 확보합니다.

## 8. DDRAM Cursor Address

16x2 LCD 기준 첫 번째 Row의 시작 Address는 0x00, 두 번째 Row의 시작 Address는 0x40으로 사용했습니다. Set DDRAM Address Command를 만들기 위해 Bit 7을 1로 설정합니다.

    uint8_t address = (row == 0U) ? col : (uint8_t)(0x40U + col);
    LCD_WriteCommand((uint8_t)(0x80U | address));

Row와 Column은 각각 0-1, 0-15 범위로 제한합니다.

## 9. 핵심 학습 포인트

- GPIO 출력만으로 LCD의 Command/Data Interface를 구현할 수 있습니다.
- RS, R/W 및 E의 역할을 구분하면 LCD Register 선택과 Write Timing을 이해할 수 있습니다.
- 8-bit 방식과 4-bit 방식은 GPIO 사용량과 전송 횟수 사이의 Trade-off를 가집니다.
- 4-bit 방식은 상위 Nibble을 먼저 보내고 하위 Nibble을 이어서 보내야 합니다.
- DDRAM Address와 Set Address Command를 구분하여 Cursor 위치를 계산해야 합니다.
- R/W를 GND에 고정하면 Busy Flag를 읽을 수 없으므로 초기화 및 명령 사이의 대기 시간을 Software Delay로 보장해야 합니다.
- 초기화 Nibble과 Driver 함수가 해석하는 Bit 위치를 일치시켜 4-bit 전환 순서를 명확히 구성했습니다.

## 10. 검증 상태

- 실제 학습 메일의 CubeMX Pinout, 배선 자료, 초기화 순서 및 코드 화면을 대조했습니다.
- STM32F411 Reference Manual과 HAL/LL User Manual을 바탕으로 GPIO Output 및 HAL_GPIO_WritePin() 동작을 정적 검토했습니다.
- 두 버전의 Driver Source는 HAL Stub을 이용한 C 문법 및 경고 검사를 통과했습니다.
- 전체 .ioc와 CubeIDE 프로젝트는 현재 보관본에 포함되지 않았습니다.
- 이번 정리 과정에서는 CubeIDE 재빌드와 STM32F411RE/LCD 실물 재시험을 수행하지 않았습니다.
