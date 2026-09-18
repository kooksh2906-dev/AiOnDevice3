# 비교군 B — EdgeScope-Lite Hardware Capture

FPGA가 100 MHz로 probe를 샘플링하고 1,024×32-bit dual-port BRAM에 trigger
전후 데이터를 저장한다. CPU는 실시간 캡처에 관여하지 않고 `DONE` 이후에만
Port B를 읽는다.

## 구현 상태

| 항목 | 상태 |
|---|---|
| Probe Sampler AXI4-Lite IP | 구현·패키징·합성 통과 |
| Basic Trigger Engine AXI4-Lite IP | 구현·패키징·합성 통과 |
| Circular Trace Buffer + Capture BRAM | 통합·합성 통과 |
| MicroBlaze V SoC | 구현·배치배선·Bitstream 통과 |
| Vitis standalone 앱 | Release `-O2` ELF 빌드 통과 |
| Bootable Bitstream | ELF 삽입 완료 |
| Basys3 실측 | 보드 연결 후 실행 필요 |

## 주소 맵

| 영역 | Base | Range |
|---|---:|---:|
| 공통 Generator GPIO | `0x4000_0000` | 64 KiB |
| Probe Sampler CSR | `0x4001_0000` | 4 KiB |
| Trigger Engine CSR | `0x4002_0000` | 4 KiB |
| Trace Buffer CSR | `0x4003_0000` | 4 KiB |
| Capture BRAM | `0x4200_0000` | 4 KiB |

최종 BSP가 생성한 `xparameters.h`에서도 위 주소를 확인한다.

### 프로젝트 진행 기록과의 주소 차이

Notion의 Day 2 기록에 남은 최초 통합 설계는 Sampler `0x44A0_0000`,
Trigger `0x44A1_0000`, Trace `0x0002_0000`, Capture BRAM
`0xC000_0000`을 사용한다. 이 디렉터리의 빌드는 A/B 비교를 공통 Base SoC에서
재현하기 위해 위 표의 독립 주소맵을 사용한다. 기능과 레지스터 규약은 같으며,
소프트웨어는 가능한 경우 항상 BSP의 `xparameters.h` 값을 우선 사용한다.

## 전체 재현 빌드

프로젝트 루트에서 실행한다.

```bash
vivado -mode batch -source scripts/package_frontend_ips.tcl
vivado -mode batch -source scripts/package_trace_buffer_ip.tcl
vivado -mode batch -source comparison/edgescope_lite/hw/block_design.tcl
vivado -mode batch -source comparison/edgescope_lite/hw/build_all.tcl

XILINX_VITIS_DATA_DIR=/tmp/edgescope_lite_vitis_data \
vitis -s comparison/edgescope_lite/vitis/build_edgescope_lite.py
```

마지막 Vitis 명령은 XSA에서 새 플랫폼을 만들고 앱을 컴파일한 뒤
`updatemem`까지 실행한다.

Sampler→Trigger AXI 레지스터와 rising/pattern one-shot 경로는 XSim으로
별도 검사할 수 있다.

```bash
./scripts/run_frontend_axi_xsim.sh
```

주요 결과:

```text
hw/edgescope_lite_reference.xsa
vitis_artifacts/edgescope_lite_app.elf
vitis_artifacts/edgescope_lite_app.bit
reports/utilization.rpt
reports/timing_summary.rpt
reports/drc.rpt
```

## 보드 실행

Basys3를 USB로 연결하고 다음을 실행한다.

```bash
vivado -mode batch \
  -source comparison/edgescope_lite/vitis/program_bitstream.tcl
python3 scripts/cpu_polling_gui.py
```

GUI에서 Basys3 UART 포트를 선택한다. UART는 `9600 baud, 8-N-1`이다.
GUI는 현재 펌웨어의 `EDGESCOPE_LITE_REFERENCE` 형식뿐 아니라 Day 3 기록의
`EDGE_SCOPE_LITE` + `RATE` + `DEPTH` Hex 형식과
`index,ch7,...,ch0` CSV 파일도 읽는다. 샘플 인덱스 누락·중복·범위 초과가
있으면 파형으로 오인하지 않고 `DATA CHECK` 경고를 표시한다. 파형 패널은
`PNG 저장`으로 바로 내보낼 수 있다.

| 명령 | 동작 |
|---|---|
| `b` | 100 MS/s Hardware Sample Rate 요약 |
| `r` | CH0 Rising 캡처와 1,024-sample dump |
| `f` | CH0 Falling 캡처와 dump |
| `p` | `A0/F0` masked pattern 캡처와 dump |
| `h` | pattern hold one-shot 캡처와 dump |
| `z` | zero-mask no-trigger 검증 |
| `s` | 1~100,000 cycle Pulse Stress |
| `q` | 종료 |

## 캡처 제어 순서

```text
Sampler Disable/Config
→ Trigger Clear
→ Trace Abort/ARM
→ Sampler Enable
→ PRE_READY
→ Trigger Clear
→ Trigger ARM
→ Generator Start
→ DONE
→ Sampler Disable
→ BRAM logical-order read
```

Trigger `CLEAR`와 `ARM`은 반드시 별도 AXI write로 보낸다. CPU는
`START_ADDR`를 기준으로 `physical=(start+logical)&0x3ff`를 적용한다.

## 현재 빌드 결과

- Slice LUT: 3,205 / 20,800
- Slice Register: 3,046 / 41,600
- RAMB36E1: 33 / 50 (`32` local memory + `1` capture)
- DSP: 0
- 100 MHz WNS: `+0.832 ns`
- Hold slack: `+0.028 ns`
- Timing failing endpoint: 0
- Bitstream DRC error: 0

이 수치는 전체 `Base SoC + EdgeScope-Lite` 결과다. 실제 trigger/pulse 결과는
보드에서 실행한 UART 원본을 별도로 저장하기 전까지 실측으로 표기하지 않는다.
