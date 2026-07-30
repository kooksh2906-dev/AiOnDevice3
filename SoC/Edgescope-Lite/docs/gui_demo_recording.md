# GUI 시연 영상 촬영 가이드

`EdgeScope_Lite_GUI_Demo_Scenario.md`를 GUI에서 그대로 촬영하기 위한 조작
순서입니다. 대상 GUI는 [`scripts/cpu_polling_gui.py`](../scripts/cpu_polling_gui.py)
하나이며, `dashboard/`의 TypeScript Dashboard는 Mock 전용이므로 촬영에
사용하지 않습니다.

## 실행

```bash
.venv/bin/python scripts/cpu_polling_gui.py --analyzer edgescope_lite
```

`--analyzer edgescope_lite`는 처음부터 **B · EdgeScope-Lite** Tab을
선택해서 열기 때문에 촬영 중 Tab을 바꾸는 장면이 필요 없습니다. Browser가
자동으로 열리지 않으면 직접
`http://127.0.0.1:8765/?analyzer=edgescope_lite`를 엽니다.

보드 없이 화면 구성만 리허설할 때는 `데모 모드`를 사용합니다. 이때 모든
수치에 `DEMO · 예상` badge가 붙으므로 영상에는 쓰지 않습니다.

## 촬영 순서

| Scene | 조작 | 화면에서 확인할 것 |
|---|---|---|
| 3 · Connection | Port 선택 → `보드 연결` | `LIVE · B · EdgeScope-Lite`, 초록 dot |
| 4 · Rising 설정 | `DEMO 1 – Rising CH0 100M` | Settings에 `1 / 1`, `100.00 MS/s`, `10 ns` |
| 5 · Arm | Preset이 `r`을 자동 전송 | `CAPTURE 수신 중 400 / 1,024` 진행 표시 |
| 6 · 전체 파형 | — | `CAPTURE VALID`, 4개 검증 모두 `PASS` |
| 7 · Trigger 확대 | `Trigger 확대` | 시간축 `-640 ns … 0 ns … +630 ns` |
| 8 · Pre/Post | 파형 클릭 | Data 패널의 Index/Time/Hex/CH7…CH0 |
| 9 · Falling | `DEMO 2 – Falling CH1 12.5M` | 아래 **Demo 2 제약** 참조 |
| 10 · Pattern | `DEMO 3 – Pattern A0/F0` | `Sample[512] = 0xA? · Mask 0xF0 · MATCH` |
| 11 · Export | `CSV 저장`, `PNG 저장` | 1,024행 CSV, 파형 PNG |

`Trigger 확대`는 `[448, 576)` 구간을 표시합니다. Trigger 선은 Sample 중심이
아니라 logical index 512의 시작 경계에 놓이므로 `[511] → [512]` 전이와
`t = 0`이 정확히 같은 x 좌표에 나타납니다.

## 자동 검증 (시나리오 §2.4)

캡처가 완성되면 GUI가 다음을 스스로 판정하고 `CAPTURE VALID` /
`CAPTURE INVALID`를 표시합니다.

| 검사 | 규칙 |
|---|---|
| Samples | `received == 1024` |
| Trigger | `trigger_index == 512` |
| Condition (Rising) | `CHx[511] == 0 && CHx[512] == 1` |
| Condition (Falling) | `CHx[511] == 1 && CHx[512] == 0` |
| Condition (Pattern) | `(sample[512] & mask) == (value & mask)` |
| Entry edge (Pattern) | `(sample[511] & mask) != (value & mask)` |
| Sample rate | 보고된 sample rate와 divider |

`PATTERN HOLD`는 진입 edge를 요구하지 않으므로 Entry edge가 `N/A`로
표시됩니다. 검증에 실패하면 어떤 항목이 깨졌는지 그 자리에서 보이므로,
촬영을 멈추고 다시 캡처하면 됩니다.

## 설정 표시가 read-only인 이유 (시나리오 §2.5)

현재 Firmware는 PC→보드 설정 명령을 지원하지 않고 단일 문자 명령
`b r f p h z s q`만 받습니다. 따라서 GUI는 설정 입력란을 제공하지 않고
**보드가 실제로 사용한 값만** 표시하며, 각 값의 출처를 badge로 밝힙니다.

| Badge | 뜻 |
|---|---|
| `UART` | Firmware가 그 값을 직접 보고했음 |
| `DERIVED` | 보고된 데이터에서 계산했음 (예: `SAMPLE_HZ`로 divider, 511→512 전이로 edge channel) |
| `FW FIXED` | 보고되지 않아 Firmware에 고정된 값을 표시함 |

`dump_capture()`가 `SAMPLE_DIVIDER`, `CHANNEL_MASK`, `TRIGGER_CHANNEL`,
`PATTERN_VALUE`, `PATTERN_MASK`를 함께 출력하도록 확장되어 있습니다.
Vitis에서 재빌드해 보드에 올리면 해당 항목이 `FW FIXED` → `UART`로 바뀝니다.
재빌드하지 않아도 GUI는 그대로 동작합니다.

## Demo 2 제약

시나리오 §3.2는 `Sample Divider 8`, `12.5 MS/s`, `Edge Channel CH1`을
요구하지만, 현재 Firmware는 divider 1과 trigger CH0으로 고정되어 있어
이를 보드에 지시할 수 없습니다
(`EDGESCOPE_DIVIDER_CODE`, `config_for_mode()`의 `.channel = 0u`).

`DEMO 2` 버튼에는 `FW 제한` badge가 붙어 있고, 누르면 이 사실을 알리는
안내가 표시됩니다. Falling 캡처 자체는 실제로 실행되며 GUI는 보드가 실제로
사용한 설정만 보여줍니다. 시나리오의 표현을 지키려면 **둘 중 하나**를
선택하십시오.

1. Firmware에 divider/trigger channel 설정 명령을 추가한다. RTL과
   `sw/include/logic_analyzer_regs.h`에 `SAMPLER_DIVIDE_BY_8`과
   `TRIGGER_CONFIG_CHANNEL_MASK`가 이미 있으므로 C만 확장하면 되고,
   GUI는 divider 8·12.5 MS/s·80 ns·CH1을 이미 처리할 수 있습니다.
2. 내레이션에서 Demo 2를 `Falling CH0 100 MS/s`로 바꾸고, Divider 설명은
   Frozen 사양에 존재하는 기능으로만 언급한다.

Firmware가 지원하지 않는 설정을 GUI 버튼으로 흉내 내면 안 된다는 시나리오
§2.5 원칙에 따라, GUI는 어느 쪽도 임의로 가정하지 않습니다.

## 촬영 전 점검

```bash
.venv/bin/python -c "import serial"          # pyserial 설치 확인
.venv/bin/python scripts/cpu_polling_gui.py --help
```

- UART는 9,600 8-N-1이며 다른 Serial Terminal과 Port를 동시에 열 수 없습니다.
- 1,024 Sample dump는 9,600 baud에서 약 11초가 걸립니다. 이 구간에는
  `CAPTURE 수신 중 n / 1,024`가 표시되며, 전송이 끝나기 전에는 검증을
  실행하지 않으므로 잘못된 무결성 경고가 나오지 않습니다.
- 녹화는 1920×1080을 권장합니다. 해당 해상도에서 파형, 검증, 설정, Data
  패널이 스크롤 없이 한 화면에 들어갑니다.
