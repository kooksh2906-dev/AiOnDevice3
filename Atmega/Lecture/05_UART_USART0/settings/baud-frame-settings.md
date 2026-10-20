# Baud Rate 및 Frame Setting

## 1. 9600 bps 설정

| 항목 | 값 |
|---|---:|
| F_CPU | 16,000,000 Hz |
| U2X0 | 1 |
| Divider | 8 |
| UBRR0 | 207 |
| 실제 Baud Rate | 약 9,615.38 bps |
| 목표 대비 오차 | 약 +0.16% |

```text
UBRR0 = round(F_CPU / (8 * BAUD)) - 1
      = round(16,000,000 / (8 * 9,600)) - 1
      = 207
```

## 2. 8N1 Frame

| 구간 | 길이 | Logic Level/순서 |
|---|---:|---|
| Idle | 가변 | High |
| Start | 1 bit | Low |
| Data | 8 bit | LSB first |
| Parity | 없음 | N(None) |
| Stop | 1 bit | High |

1 Character는 Start 1 + Data 8 + Stop 1로 총 10 bit를 사용합니다. 따라서 9600 bps에서 이론적인 최대 8-bit Character Rate는 약 960 character/s입니다.

## 3. Double Speed의 의미

- Normal Asynchronous Mode는 Baud Generator를 16으로 나눕니다.
- Double Speed Asynchronous Mode는 U2X0=1로 Divider를 8로 줄입니다.
- Receiver Sample 수는 bit당 16회에서 8회로 줄어 Clock와 Baud 오차에 대한 허용 범위가 더 엄격해질 수 있습니다.
- 16 MHz/9600 bps에서는 UBRR0=207의 오차가 충분히 작아 원자료 설정과 일치합니다.
