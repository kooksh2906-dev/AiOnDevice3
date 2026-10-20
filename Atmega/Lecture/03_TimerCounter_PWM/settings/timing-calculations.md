# Timing Calculations

모든 계산은 시스템 Clock 16 MHz를 기준으로 합니다.

## Timer0 CTC Toggle

```text
Prescaler N = 64
OCR0 = 124
Compare interval = N × (1 + OCR0) / F_CPU
                 = 64 × 125 / 16,000,000
                 = 0.5 ms

OC0 output period = 2 × Compare interval = 1 ms
OC0 output frequency = 1 kHz
```

OC0는 Compare Match마다 Toggle되므로 완전한 한 주기에는 두 번의 Compare Match가 필요합니다.

## Timer0 Normal Overflow

```text
Prescaler N = 128
TCNT0 preload = 6
Counts to overflow = 256 - 6 = 250
Overflow interval = 250 × 128 / 16,000,000 = 2 ms

Software-toggle period = 2 × 2 ms = 4 ms
Nominal frequency = 250 Hz
```

실제 주기에는 Flag 확인, PORT 반전 및 TCNT0 재기록 명령 시간이 포함됩니다.

## Timer0 Fast PWM

```text
Prescaler N = 64
TOP = 255
PWM frequency = F_CPU / (N × 256)
              = 16,000,000 / (64 × 256)
              = 976.5625 Hz
```

비반전 Fast PWM의 일반 비교값에서 High 비율은 다음과 같이 해석할 수 있습니다.

```text
Duty ≈ (OCR0 + 1) / 256
OCR0 = 64 -> 65 / 256 ≈ 25.39%
```

`OCR0=0`은 매 주기 좁은 Spike, `OCR0=255`는 Constant High가 되는 특수 조건입니다.

## Timer1 Mode 14 Fast PWM

```text
Prescaler N = 64
Timer tick = 64 / 16,000,000 = 4 us
ICR1 = 4999
Period = (1 + ICR1) × 4 us = 20 ms
Frequency = 50 Hz
```

### OCR1A 값

| OCR1A | High Count | High Pulse | Duty |
|---:|---:|---:|---:|
| 1249 | 1250 | 5.000 ms | 25.00% |
| 630 | 631 | 2.524 ms | 12.62% |
| 254 | 255 | 1.020 ms | 5.10% |
| 120 | 121 | 0.484 ms | 2.42% |

비반전 Mode 14에서 High Pulse는 대략 `(OCR1A + 1) × Timer Tick`으로 계산합니다.
