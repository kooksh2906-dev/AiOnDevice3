# Circular Trace Buffer — Steps 1–9 Audit and Final Verification

검증일: 2026-07-27  
담당: 윤형욱  
Tool: Icarus Verilog + Vivado 2024.2  
Part: `xc7a35tcpg236-1`

## 결론

1–9단계 산출물을 공통명세 Frozen v2.1과 다시 대조하고 전체 회귀,
IP 재패키징, BD parameter propagation, standalone/integrated synthesis,
routed timing을 재실행했다. 감사에서 발견한 통합 결함은 모두 수정했고 현재
재현 가능한 검증은 PASS다.

## 감사에서 발견하고 수정한 항목

| 우선순위 | 발견 내용 | 수정 및 재검증 |
|---|---|---|
| P0 | Trigger Engine을 먼저 ARM하면 PREFILL 중 one-shot pulse가 소진될 수 있음 | `Buffer ARM → PRE_READY poll → Trigger ARM`을 v2.1 필수 순서로 동결, PREFILL/512번째 trigger 무시 TB 추가 |
| P0 | BRAM interface 기본 `MEM_SIZE=8192`가 BD BMG depth를 2048로 변경 | packaged/external interface를 4096 bytes로 고정하고 Tcl에서 propagated depth=1024 assertion 추가 |
| P1 | Packaged IP GUI가 미지원 AXI width 변경을 허용 | packaged top AXI address/data 폭을 6/32로 고정 |
| P1 | `irq_o`가 일반 scalar port로만 등록 | IP-XACT `interrupt` master, `SENSITIVITY=LEVEL_HIGH` 추가 |
| P1 | CPU 예제가 register offset을 값처럼 사용 | `Xil_In32(TRACE_BASEADDR + TRACE_REG_START_ADDR)`로 정정 |
| P1 | BRAM TB가 실제 packaged top을 우회 | `circular_trace_buffer_ip` top과 clock/reset/address adapter를 직접 검증하도록 변경 |
| P2 | AXI response stall과 partial transaction reset 미검증 | B/R back-pressure 안정성 및 AW-only/W-only reset test 추가 |
| P2 | synchronous reset에 false-path 적용 | false-path 제거, setup/hold와 route status를 각각 gate |
| P2 | package constant/timescale 경고 | frozen 값은 `localparam`으로 명시하고 공통 TB timescale 추가 |

## 회귀 테스트

실행 명령:

```bash
./scripts/run_regression.sh --waves
```

| Test | 핵심 검증 | 결과 |
|---|---|---|
| `tb_common_pkg` | spec v2.1, width/depth/count 상수 | PASS |
| `tb_circular_trace_buffer_basic` | reset, ARM, valid gating, exact prefill, early trigger ignore | PASS |
| `tb_circular_trace_buffer_trigger` | trigger sample alignment, post 512, logical order, write stop | PASS |
| `tb_circular_trace_buffer_wrap` | trigger physical 0/1/1022/1023, wrap order | PASS |
| `tb_circular_trace_buffer_control` | abort/clear/arm priority, DONE/IRQ hold, re-arm | PASS |
| `tb_circular_trace_buffer_axi` | offsets, W1P, WSTRB, AW/W order, B/R stall, partial reset | PASS |
| `tb_circular_trace_buffer_bram` | packaged top, byte conversion, 1024 Port-B reads | PASS |
| C `_Static_assert` | register header offsets/bits/geometry/info encoding | PASS |

원본 VCD 6개는 `artifacts/waves/`에 저장했고, trigger 회귀 VCD에서 직접 생성한
발표용 이미지가
[circular_trace_buffer_waveform.png](circular_trace_buffer_waveform.png)이다.

## Vivado 검증

### Custom IP

| 항목 | 결과 |
|---|---:|
| VLNV | `user.org:user:circular_trace_buffer:1.0` |
| AXI / BRAM / IRQ metadata | Slave / 4096-byte master / level-high interrupt |
| IP integrity and catalog load | PASS |
| BD validation | PASS |
| Routed nets | 140 / 140, error 0 |
| Slice LUT / FF | 73 / 90 |
| Setup WNS / TNS | `+4.978 ns` / `0.000 ns` |
| Hold WHS / THS | `+0.170 ns` / `0.000 ns` |

### BRAM and Integrated Subsystem

| 항목 | 결과 |
|---|---:|
| Generated BMG | 1024 × 32-bit, true dual port, common 100 MHz clock |
| Interface memory size | 4096 bytes on Port A/B |
| Standalone BMG synthesis | 1 RAMB36E1, 0 LUT, 0 FF |
| Integrated Trace+BMG+AXI BRAM Controller | 338 LUT, 306 FF, 1 RAMB36E1, 0 DSP |

생성 XCI의 `C_WRITE_DEPTH_A/B=1024`, `C_COMMON_CLK=1`을 확인했고 통합 합성
netlist에서도 RAMB36E1이 정확히 1개인지 Tcl로 검사했다.

## 남은 시스템 단위 확인

- `+4.978 ns`는 Custom IP 내부 OOC 결과다. 최종 MicroBlaze 전체 Block Design의
  implementation에서 I/O 포함 setup/hold를 다시 sign-off한다.
- AXI BRAM Controller의 12-bit byte address가 BMG 32-bit address의 lower bits에
  연결된다는 BD width warning은 4 KiB 영역에서는 의도된 동작이다.
- BMG의 개별 OOC checkpoint는 생성 기본값인 20 ns clock으로 만들 수 있어
  통합 시 10 ns clock과 다르다는 경고가 나타날 수 있다. 메모리 형상·기능에는
  영향이 없으며 최종 전체 BD implementation은 실제 10 ns 제약으로 sign-off한다.
- Vivado 사용자 Tcl store write 권한 및 폴더명 공백에 대한 `setupEnv.sh` 메시지는
  이 환경의 tool-launch warning이며 합성/검증 결과에는 영향을 주지 않았다.

## 증거 파일

- `build/trace_buffer_timing_summary.rpt`
- `build/trace_buffer_route_status.rpt`
- `build/trace_buffer_utilization.rpt`
- `build/capture_bram_utilization.rpt`
- `build/packaged_trace_buffer_system_utilization.rpt`
- `build/circular_trace_buffer_ip_routed.dcp`
- `build/packaged_trace_buffer_system_synth.dcp`
