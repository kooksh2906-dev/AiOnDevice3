# Custom Analyzer 전체 Routed 보고서 제출 계약

Step 9의 공식 `Custom vs Vivado ILA` 자원 절감률을 확정하려면 이 폴더에
동일한 Implementation Run에서 생성한 다음 파일 7개를 넣는다.

```text
utilization.rpt
hierarchical_utilization.rpt
timing_summary.rpt
route_status.rpt
drc.rpt
routed_design.dcp
build_manifest.rpt
```

IP 단독 OOC 결과, Subsystem Synthesis 결과, Resource Summary 화면 캡처,
XSA의 Summary 값은 전체 Routed 결과를 대신할 수 없다.

## 1. 필수 구현 조건

- Vivado `2024.2`
- Digilent Basys 3
  - FPGA Part: `xc7a35tcpg236-1`
  - Board Part: `digilentinc.com:basys3:part0:1.2`
- Top: `base_soc_wrapper`
- `sys_clock`: 100 MHz, Period `10.000 ns`
- Synthesis Strategy: `Vivado Synthesis Defaults`
- Implementation Strategy: `Vivado Implementation Defaults`
- 공통 Base SoC와 Test Pattern Generator 포함
- 다음 Custom 계층을 각각 정확히 1개 포함
  - Probe Sampler
  - Trigger Engine
  - Circular Trace Buffer
  - AXI BRAM Controller
  - Capture BRAM
- Capture BRAM 계층의 Primitive 사용량: `RAMB36=1`, `RAMB18=0`
- 비교 결과를 보기 위한 추가 ILA, VIO, Debug Hub 제외

Custom IP뿐 아니라 공통 MicroBlaze SoC가 빠짐없이 포함됐다는 것을 증명하기
위해 Hierarchical Utilization Report에는 다음 `(Instance, Module)` 행이
각각 정확히 1개 있어야 한다.

| Instance | Module |
|---|---|
| `base_soc_i` | `base_soc` |
| `axi_gpio_test_ctrl` | `base_soc_axi_gpio_test_ctrl_0` |
| `axi_timer_0` | `base_soc_axi_timer_0_0` |
| `axi_uartlite_0` | `base_soc_axi_uartlite_0_0` |
| `clk_wiz` | `base_soc_clk_wiz_0` |
| `mdm_1` | `base_soc_mdm_1_0` |
| `microblaze_riscv_0` | `base_soc_microblaze_riscv_0_0` |
| `microblaze_riscv_0_axi_intc` | `base_soc_microblaze_riscv_0_axi_intc_0` |
| `microblaze_riscv_0_axi_periph` | `base_soc_microblaze_riscv_0_axi_periph_0` |
| `microblaze_riscv_0_local_memory` | `microblaze_riscv_0_local_memory_imp_<영숫자>` |
| `microblaze_riscv_0_xlconcat` | `base_soc_microblaze_riscv_0_xlconcat_0` |
| `rst_clk_wiz_100M` | `base_soc_rst_clk_wiz_100M_0` |
| `test_pattern_generator_gpio_adapter_0` | `base_soc_test_pattern_generator_gpio_adapter_0_0` |

Local Memory 행은 `RAMB36=32`, `RAMB18=0`이어야 한다.

Hierarchical Utilization Report에서 검증기가 인식하는 Instance 이름은 다음과
같다. 이름을 바꿔야 한다면 먼저 검증기의 동결 계약도 함께 갱신한다.

| 역할 | 허용 Instance 이름 |
|---|---|
| Probe Sampler | `probe_sampler_axi_0`, `probe_sampler_0` |
| Trigger Engine | `basic_trigger_engine_0`, `basic_trigger_engine_axi_0`, `trigger_engine_0` |
| Circular Trace Buffer | `circular_trace_buffer_0` |
| AXI BRAM Controller | `axi_bram_ctrl_0`, `axi_bram_controller_0`, `capture_axi_bram_ctrl_0` |
| Capture BRAM | `circular_trace_buffer_0_bram`, `capture_bram_0`, `trace_capture_bram_0`, `blk_mem_gen_capture_0` |

검증기는 전체 Top Hierarchy의 자원 합계가 `utilization.rpt`의 전체 합계와
같은지, 공통 Generator 계층이 동결값인지, Timing/Route/DRC가 통과했는지도
별도로 확인한다. `RAMB36`과 `RAMB18`은 합치지 않고 각각 보존한다.

Timing Report는 `report_timing_summary -report_unconstrained
-check_timing_verbose`로 생성한다. `check_timing` 12개 항목은
`0,0,0,0,2,1,0,0,0,0,0,0` 순서여야 한다. 여기서 `no_input_delay=2`,
`no_output_delay=1`은 공통 외부 포트이고, 나머지 내부 누락 항목은 모두
0이어야 한다.

DRC Report는 필터 없이 전체 설계에 대해 다음 조건으로 생성한다.

```tcl
report_drc -ruledecks {default bitstream_checks} -no_waivers \
  -file drc.rpt
```

`-checks` 또는 `-filter`로 일부 Rule만 고른 보고서는 사용할 수 없다.

## 2. `build_manifest.rpt` 작성

아래 블록을 그대로 복사한 뒤 모든 `<...>` Placeholder를 실제 값으로
교체한다. Placeholder, 따옴표, 설명 문장을 값에 남기면 안 된다.

```text
# EdgeScope-Lite Custom whole-routed-SoC build manifest
OVERALL=PASS
BUILD_SCOPE=CUSTOM_WHOLE_ROUTED_SOC
VIVADO_VERSION=2024.2
FPGA_PART=xc7a35tcpg236-1
BOARD_PART=digilentinc.com:basys3:part0:1.2
TOP=base_soc_wrapper
DESIGN_STATE=ROUTED
CLOCK_HZ=100000000
CLOCK_PERIOD_NS=10.000
SYNTHESIS_STRATEGY=Vivado Synthesis Defaults
IMPLEMENTATION_STRATEGY=Vivado Implementation Defaults
VIVADO_ILA_COUNT=0
VIO_COUNT=0
DEBUG_CORE_COUNT=0
GENERATOR_HIERARCHY_COUNT=1

GIT_COMMIT=<40_OR_64_HEX_GIT_OBJECT_ID>
GIT_WORKTREE_DIRTY=<0_OR_1>

BASE_SOC_TCL_SHA256=<64_HEX_SHA256>
GENERATOR_INTEGRATION_TCL_SHA256=<64_HEX_SHA256>
GENERATOR_RTL_SHA256=<64_HEX_SHA256>
GENERATOR_ADAPTER_SHA256=<64_HEX_SHA256>

CUSTOM_PROBE_SAMPLER_COUNT=1
CUSTOM_TRIGGER_ENGINE_COUNT=1
CUSTOM_CIRCULAR_TRACE_BUFFER_COUNT=1
CUSTOM_AXI_BRAM_CONTROLLER_COUNT=1
CUSTOM_CAPTURE_BRAM_COUNT=1
CAPTURE_BRAM_INCLUDED=YES

PROBE_SAMPLER_SOURCE_SHA256=<64_HEX_SHA256>
TRIGGER_ENGINE_SOURCE_SHA256=<64_HEX_SHA256>
CIRCULAR_TRACE_BUFFER_SOURCE_SHA256=<64_HEX_SHA256>
CAPTURE_BRAM_SOURCE_SHA256=<64_HEX_SHA256>

ROUTED_DCP_SHA256=<64_HEX_SHA256>
UTILIZATION_REPORT_SHA256=<64_HEX_SHA256>
HIERARCHICAL_REPORT_SHA256=<64_HEX_SHA256>
TIMING_REPORT_SHA256=<64_HEX_SHA256>
ROUTE_REPORT_SHA256=<64_HEX_SHA256>
DRC_REPORT_SHA256=<64_HEX_SHA256>
```

`GIT_COMMIT`에는 실제 Git Object ID를 기록한다. `GIT_WORKTREE_DIRTY`는
깨끗하면 `0`, 미Commit 변경이 있으면 `1`이다. Dirty 상태도 허용하지만
반드시 사실대로 기록하고 해당 Source를 보존한다.

공통 Source Hash는 저장소 루트에서 다음 명령으로 구한다. 검증기는 이 네
값을 현재 동결된 공통 Source와 직접 대조한다.

```bash
sha256sum \
  comparison/common/base_soc.tcl \
  comparison/common/add_test_pattern_generator.tcl \
  comparison/common/rtl/test_pattern_generator.sv \
  comparison/common/rtl/test_pattern_generator_gpio_adapter.v
```

Custom Source Hash에는 실제로 구현에 사용한 RTL 또는 IP 설정 파일의
SHA-256을 기록한다. 이 네 값은 Build Manifest에 선언되는 값이므로 해당
Git Commit과 Source 원본을 팀 공용 저장소에 함께 보존해야 한다.
Capture BRAM이 XCI/Tcl로 생성됐다면
`CAPTURE_BRAM_SOURCE_SHA256`에 구현에 사용한 동결 XCI 또는 생성 Tcl의
Hash를 기록하고 그 원본을 함께 보존한다.

Routed DCP와 다섯 Report의 Hash는 다음처럼 구한다. 실제 DCP 경로를
`<ROUTED_DCP_PATH>` 대신 넣는다.

```bash
sha256sum \
  routed_design.dcp \
  utilization.rpt \
  hierarchical_utilization.rpt \
  timing_summary.rpt \
  route_status.rpt \
  drc.rpt
```

검증기는 이 폴더에 있는 다섯 Report와 `routed_design.dcp`의 Hash를
Manifest 값과 직접 대조한다.

## 3. 자동 검증 및 결과 무결성 확인

파일 7개를 넣은 뒤 저장소 루트에서 실행한다.

```bash
comparison/ila_reference/run_step9_resource_timing.sh
```

검증에 실패하면 다음 파일에서 `ASSERT...=FAIL` 항목을 먼저 확인한다.

```text
comparison/ila_reference/results/step9/resource_timing_validation.rpt
```

검증 통과 후 생성된 Step 9 결과의 SHA-256을 확인한다.

```bash
(
  cd comparison/ila_reference/results/step9
  sha256sum -c SHA256SUMS
)
```

모든 항목이 `OK`여야 한다. 공식 표는 전체 Routed `Total`과
`Total - Common Base + Generator`인 `Delta`를 분리한다. 공식 절감률은
`Custom Delta`와 `Vivado ILA Delta` 사이에서만 계산하며 CPU Polling은
계산에 사용하지 않는다.

## 4. 공식 표에서 제외되는 현재 참고값

- 팀 전달 합성 Summary: LUT `2,933`, FF `2,802`, BRAM 표시 `33`
  - 전체 Routed Report가 아니고 RAMB36/RAMB18 구분과 Timing 원본이 없음
- Packaged Subsystem Synthesis: LUT `338`, FF `306`, RAMB36E1 `1`
  - MicroBlaze 전체 SoC 범위가 아님
- Circular Trace Buffer OOC Route: LUT `73`, FF `90`, WNS `+4.978 ns`
  - Custom IP 단독 범위이고 Capture BRAM이 포함되지 않음
- `edgescope_lite_bd_wrapper.xsa`
  - Bitstream과 HWH/BDA는 있으나 Routed DCP, Utilization, Timing, Route,
    DRC Report가 들어 있지 않음

위 값은 구현이 잘못됐다는 뜻이 아니라 측정 범위가 공식 비교 조건과
다르다는 뜻이다. 숫자를 `0`으로 대입하거나 ILA 전체 Routed Total과 직접
비교하지 않는다.
