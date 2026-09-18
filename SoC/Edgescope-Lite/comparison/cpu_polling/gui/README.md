# A/B/C Logic Analyzer GUI

A CPU Polling, B EdgeScope-Lite, C Vivado ILA를 하나의 Python 로컬
서버와 브라우저 화면에서 비교한다. 기존 MicroBlaze UART 단일 문자
프로토콜은 유지하며, C만 ILA를 먼저 arm한 뒤 UART 자극을 전송한다.

## 바로 시연하기

프로젝트 루트에서 실행한다.

```bash
python3 scripts/cpu_polling_gui.py
```

브라우저가 자동으로 `http://127.0.0.1:8765`를 연다. 상단 탭에서 A/B/C를
전환한다. 보드가 없어도 A의 저장된 `results/uart_capture.log`와, 이 파형을
100 MHz hardware-capture 형식으로 변환한 B/C 미리보기를 시연할 수 있다.

- Rising/Falling/Pattern/Pattern Hold 8채널 파형
- Trigger logical index 512와 pre/post 구간
- Trigger mode별 Polling benchmark
- Pulse 폭별 검출률
- Zero-mask no-trigger PASS
- A 1.67 MS/s와 B/C 100 MS/s 비교
- A/B/C Vivado 보고서의 LUT, Register, BRAM, WNS 비교
- B의 `START_ADDR`, `TRIGGER_ADDR`, `WRITE_ADDR`
- C의 Vivado ILA buffer, trigger, JTAG CSV evidence

B/C 미리보기의 처리량과 Pulse 결과에는 `DEMO`가 표시된다. 이는 설계
사양에 따른 예상 화면이며 보드 실측값으로 표시하지 않는다. C 실측 CSV를
가져오거나 자동 JTAG 캡처가 완료된 경우에만 C가 `IMPORTED` 또는
`MEASURED` evidence로 바뀐다.

브라우저가 자동으로 열리지 않으면 출력된 주소를 직접 연다. 다른 포트는
`--port 9000`, 브라우저 자동 실행을 끄려면 `--no-browser`를 사용한다.

## Basys3 실시간 연결

Python 패키지 `pyserial`이 있어야 UART 포트가 목록에 표시된다.

```bash
python3 -m pip install pyserial
python3 scripts/cpu_polling_gui.py
```

1. 선택한 비교 방식의 Vitis bitstream을 Basys3에 프로그램한다.
   C는 `comparison/vivado_ila/vitis_artifacts/vivado_ila_app.bit`과
   `comparison/vivado_ila/hw/vivado_ila_reference.ltx`를 사용한다.
2. GUI의 UART 목록에서 보드 포트를 고르고 **연결**을 누른다.
3. 캡처 또는 시험 버튼을 누른다.

연결 설정은 기존 앱과 같은 `9600 baud, 8-N-1`이다. A/B는 기존
`b/r/f/p/h/z/s` UART 프로토콜을 유지한다. C의 `r/f/p/h`는 JTAG ILA를 먼저
arm한 뒤에만 UART로 전송한다. C 탭에서 `b`는 고정 100 MHz sample clock을
표시하며, 전용 재-arm 절차가 아직 필요한 `s/z`는 자극을 보내지 않고 안내한다.

GUI는 `CPU_POLLING_REFERENCE_READY`,
`EDGESCOPE_LITE_REFERENCE_READY`,
`VIVADO_ILA_REFERENCE_READY`를 구분해 Live 탭을 자동 선택한다.

## Vivado ILA CSV와 자동 캡처

`UART/CSV 불러오기`는 Vivado `write_hw_ila_data -csv_file`의 2행 header
형식을 자동 인식한다. C evidence로 인정하려면 다음 조건을 모두 만족해야
한다.

- `Sample in Buffer` index가 중복 없이 정확히 `0..1023`
- 8-bit probe 값이 1,024개 모두 해석 가능
- `TRIGGER`가 정확히 index 512에서 한 번만 assert

부분 CSV, 잘못된 trigger, 중복·누락 sample은 파형으로 표시하지 않고
`DATA CHECK` 오류를 보여준다.

C 탭에서 Rising/Falling/Pattern/Pattern Hold를 누르면 GUI의
`POST /api/ila/capture`가 비동기로 Vivado Tcl을 실행한다.

```text
Vivado ILA arm
→ VIVADO_ILA_ARMED 확인
→ UART r/f/p/h 자극 전송
→ VIVADO_ILA_CAPTURE_PASS 확인
→ CSV 무결성 검사
→ GUI MEASURED 파형 갱신
```

진행 상태는 `GET /api/ila/status`로 확인한다. Tcl 인터페이스는
`EDGESCOPE_ILA_MODE`, `EDGESCOPE_ILA_CSV`, `EDGESCOPE_ILA_PROGRAM`,
`EDGESCOPE_ILA_BIT`, `EDGESCOPE_ILA_LTX` 환경 변수를 사용한다.
UART 미연결, capture Tcl/Vivado 누락은 실행 전에 오류를 반환하고,
JTAG/hw_server 미연결 또는 멈춤은 Tcl 오류나 60초 watchdog으로
종료한다. `Pattern Hold`는 UART 자극만 `h`이며 ILA trigger mode는
`PATTERN`으로 설정된다.
