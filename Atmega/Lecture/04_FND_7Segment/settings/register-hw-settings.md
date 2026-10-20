# Register & Hardware Settings

## GPIO 설정

| 대상 | 레지스터/Bit | 설정 | 의미 |
|---|---|---|---|
| Segment A | `PORTC0` | Pattern bit 0 | A Segment 출력 |
| Segment B | `PORTC1` | Pattern bit 1 | B Segment 출력 |
| Segment C | `PORTC2` | Pattern bit 2 | C Segment 출력 |
| Segment D | `PORTC3` | Pattern bit 3 | D Segment 출력 |
| Segment E | `PORTC4` | Pattern bit 4 | E Segment 출력 |
| Segment F | `PORTC5` | Pattern bit 5 | F Segment 출력 |
| Segment G | `PORTC6` | Pattern bit 6 | G Segment 출력 |
| Decimal Point | `PORTC7` | Pattern bit 7 | DP 출력 |
| Port 방향 | `DDRC[7:0]` | `0xFF` | PC0~PC7 전체 출력 |

## Port C 특성

- Port C는 PC0~PC7의 8-bit 양방향 GPIO입니다.
- Reset 초기값은 `PORTC=0x00`, `DDRC=0x00`입니다.
- ATmega103 호환 모드에서는 Port C가 출력 전용으로 동작합니다. 이 실습은 출력만 사용하지만 다른 GPIO 입력 코드로 확장할 때는 호환 모드를 확인해야 합니다.
- 외부 메모리 인터페이스를 활성화하면 PC0~PC7이 A8~A15 Address Bus로 사용될 수 있습니다. FND 전용 GPIO 실습에서는 `MCUCR.SRE=0`을 전제로 합니다.

## FND 극성

| 종류 | Segment ON | 모든 Segment OFF |
|---|---|---|
| Common Cathode / Active-High | 출력 1 | `0x00` |
| Common Anode / Active-Low | 출력 0 | `0xFF` |

원형의 `0x3F`가 숫자 0을 표시하려면 A~F가 High에서 켜져야 하므로 Active-High 배선 또는 동등한 외부 구동 회로가 필요합니다. VER4는 Common Anode 선택 시 Pattern 전체를 반전합니다.

## Timing

- 원형과 함수형 실습은 `_delay_ms(500)`으로 숫자를 0.5초마다 변경합니다.
- `_delay_ms()`는 Blocking Delay이며 정확한 지연 계산에는 올바른 `F_CPU` 빌드 설정이 필요합니다.
- VER1~VER4는 1자리 FND이므로 Multiplexing Refresh 주기나 자리 선택 신호를 사용하지 않습니다.

## VER5 4-digit 예시 GPIO

| 대상 | Register/Bit | 설정 | 의미 |
|---|---|---|---|
| Segment Bus | `PORTC[7:0]` | Active-Low Pattern | A~G·DP 공유 출력 |
| Digit 0 | `PORTA0` | Active-Low | 1의 자리 선택 |
| Digit 1 | `PORTA1` | Active-Low | 10의 자리 선택 |
| Digit 2 | `PORTA2` | Active-Low | 100의 자리 선택 |
| Digit 3 | `PORTA3` | Active-Low | 1000의 자리 선택 |
| Segment 방향 | `DDRC=0xFF` | 전체 출력 | 공유 Segment Bus |
| Digit 방향 | `DDRA[3:0]=1` | 하위 4-bit 출력 | 다른 Port A bit 설정 보존 |

- `PORTA`와 `DDRA`의 Reset 초기값은 모두 0입니다.
- Port A는 외부 메모리 인터페이스에서 `AD7:0`, Port C는 `A15:8` 역할을 하므로 VER5 역시 `MCUCR.SRE=0`을 전제로 합니다.
- 1자리당 1 ms씩 표시하면 한 Frame은 약 4 ms이고, 각 자리는 약 250 Hz로 갱신됩니다.
- 자리 변경 순서는 `전체 자리 OFF → Segment 갱신 → 해당 자리 ON → 1 ms 유지 → 전체 자리 OFF`입니다.
- `FND4_COUNT_PERIOD_MS=100`이면 25 Frame마다 숫자가 1 증가하며, 이 값만 바꿔 Count 속도를 조절할 수 있습니다.
