# 비교군 C — Vivado ILA Reference

공통 Base SoC와 Test Pattern Generator에 Xilinx Vivado ILA를 연결한
Hardware Analyzer 기준군이다. ILA는 100 MHz에서 `probe_test_o[7:0]`을
직접 샘플링하며, MicroBlaze는 UART 명령을 받아 공통 Generator만 시작한다.
샘플은 UART가 아니라 JTAG를 통해 Vivado CSV로 내보낸다.

## 구현 상태

| 항목 | 상태 |
|---|---|
| Vivado ILA v6.2 Block Design | 구현·검증 통과 |
| Synthesis/Implementation/Bitstream | 통과 |
| XSA 및 LTX | 생성 완료 |
| MicroBlaze Generator 제어 앱 | Vitis Release `-O2` 빌드 통과 |
| Bootable Bitstream | ELF 삽입 완료 |
| Python A/B/C GUI 및 CSV 파서 | 구현 |
| Basys3 JTAG 실측 | 보드 연결 후 실행 필요 |

## 동결 설정

| 항목 | 값 |
|---|---:|
| ILA IP | `xilinx.com:ip:ila:6.2` |
| Sample clock | 100 MHz |
| Probe | 8 bit, 1개 |
| Capture depth | 1,024 |
| Trigger position | 512 |
| Window count | 1 |
| Input pipeline | 0 |
| Match unit | 1 |
| Advanced trigger | 비활성 |
| Storage qualifier | 비활성 |

Trigger 비교값은 CH0 Rising `eq8'bxxxxxxxR`, CH0 Falling
`eq8'bxxxxxxxF`, `0xA0/0xF0` Masked Pattern `eq8'b1010xxxx`이다.

## 전체 재현 빌드

프로젝트 루트에서 실행한다.

```bash
vivado -mode batch \
  -source comparison/vivado_ila/hw/block_design.tcl
vivado -mode batch \
  -source comparison/vivado_ila/hw/build_all.tcl
vitis -s comparison/vivado_ila/vitis/build_vivado_ila.py
```

주요 산출물:

```text
hw/vivado_ila_reference.bit
hw/vivado_ila_reference.ltx
hw/vivado_ila_reference.xsa
vitis_artifacts/vivado_ila_app.elf
vitis_artifacts/vivado_ila_app.bit
reports/utilization.rpt
reports/hierarchical_utilization.rpt
reports/timing_summary.rpt
reports/drc.rpt
```

## GUI/JTAG 캡처

Basys3를 JTAG와 UART로 연결한 뒤 bootable bit를 프로그램한다.

```bash
vivado -mode batch \
  -source comparison/vivado_ila/vitis/program_bitstream.tcl
python3 scripts/cpu_polling_gui.py
```

GUI의 C 탭에서 캡처를 누르면 다음 순서를 지킨다.

```text
Vivado Hardware Manager 연결
→ ILA trigger 설정 및 ARM
→ VIVADO_ILA_ARMED 확인
→ UART r/f/p/h 명령 전송
→ Generator event
→ ILA upload
→ CSV export/무결성 검사
→ 8-channel 파형 표시
```

`capture_ila.tcl`은 `VIVADO_ILA_ARMED`를 출력하기 전에는 UART 자극을
보내지 않는 Python backend와 함께 사용한다. CSV는 정확히 1,024개 sample,
중복·누락 없음, 단일 trigger, trigger index 512 조건을 통과해야
`MEASURED`로 표시된다.

## 현재 Implementation 결과

| 지표 | 전체 C Build | ILA 계층 |
|---|---:|---:|
| Slice LUT | 3,726 | 591 |
| Slice Register | 4,230 | 1,034 |
| RAMB36 | 32 | 0 |
| RAMB18 | 1 | 1 |
| DSP | 0 | 0 |

- 100 MHz WNS: `+1.262 ns`
- Hold slack: `+0.024 ns`
- Setup/Hold failing endpoint: `0 / 0`
- DRC error: `0`

이 값은 `Base SoC + Generator + Vivado ILA` 전체 결과다. 실제 trigger와
Pulse 검출률은 보드에서 JTAG CSV 원본을 얻기 전까지 GUI에서 `DEMO`로
표시한다.
