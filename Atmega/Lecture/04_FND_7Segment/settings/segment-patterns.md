# Segment Patterns

## Bit 배치

```text
bit 7  bit 6  bit 5  bit 4  bit 3  bit 2  bit 1  bit 0
  DP      G      F      E      D      C      B      A
```

## 원자료 글꼴과 표준형 비교

| 숫자 | 원자료 | 표준형 | 차이 |
|---:|---:|---:|---|
| 0 | `0x3F` | `0x3F` | 동일 |
| 1 | `0x06` | `0x06` | 동일 |
| 2 | `0x5B` | `0x5B` | 동일 |
| 3 | `0x4F` | `0x4F` | 동일 |
| 4 | `0x66` | `0x66` | 동일 |
| 5 | `0x6D` | `0x6D` | 동일 |
| 6 | `0x7D` | `0x7D` | 동일 |
| 7 | `0x27` | `0x07` | 원자료는 F Segment 추가 |
| 8 | `0x7F` | `0x7F` | 동일 |
| 9 | `0x67` | `0x6F` | 원자료는 D Segment 생략 |

두 표는 전기적으로 옳고 그름의 차이가 아니라 숫자 7과 9를 그리는 글꼴 선택의 차이입니다. 원형 VER1~VER3은 제공된 표를 그대로 보존하며 VER4에서 선택할 수 있습니다.

## Decimal Point

- Active-High에서 DP ON: 숫자 Pattern에 `0x80`을 OR합니다.
- Active-Low에서는 전체 Pattern 반전 과정에 DP 상태가 함께 반영됩니다.

## VER5 4-digit 출력 극성

- FPGA SoC 예제의 Font는 표준형 `0x07`(7), `0x6F`(9)를 사용합니다.
- VER5도 같은 표준 Font를 사용해 두 플랫폼의 자리 분리·Scan 구조를 직접 비교할 수 있게 합니다.
- Segment가 Active-Low인 기본 설정에서는 `~font[digit]`의 하위 8-bit를 출력합니다.
- Digit Select가 Active-Low이면 1·10·100·1000의 자리 Pattern은 각각 `0x0E`, `0x0D`, `0x0B`, `0x07`입니다.
- `fnd4Init()`의 극성 인자를 바꾸면 Active-High Segment나 Digit Select 회로에도 같은 논리를 적용할 수 있습니다.
