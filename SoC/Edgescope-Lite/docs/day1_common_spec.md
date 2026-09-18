# EdgeScope-Lite Day 1 공통 명세 — Frozen v2.1

동결일: 2026-07-27  
기준 문서: `EdgeScope_Lite_SoC_Project_Plan.md`

v2.1 감사 보정: `PRE_READY` 이후 Trigger ARM 순서와 packaged BRAM
`MEM_SIZE=4096` metadata를 명시했다. Port, register, capture geometry 값은
v2.0과 동일하다.

이 문서는 Probe Sampler, Basic Trigger Engine, Circular Trace Buffer 사이의 연결과
각 IP의 AXI4-Lite register를 동결한다. 세 담당자는 이 문서를 단일 기준으로
사용하며, 개별 구현에서 이름이나 의미를 바꾸지 않는다.

## 1. 시스템 고정 사양

| 항목 | 확정값 |
|---|---:|
| FPGA board | Digilent Basys3, XC7A35T |
| System/capture clock | 100 MHz |
| Probe/sample width | 8 bits |
| BRAM word width | 32 bits |
| BRAM word address width | 10 bits |
| Capture depth | 1,024 words |
| Capture memory size | 4 KiB |
| AXI4-Lite CSR width | 32-bit data, 6-bit local byte address |
| Pre-trigger | 512 samples |
| Post-trigger | 512 samples, trigger sample 포함 |
| Trigger logical index | 512 |
| Reset | synchronous active-low `rst_ni` |
| HDL | SystemVerilog |

BRAM word는 다음 형식으로 저장한다.

```text
BRAM Word[31:8] = 24'h000000
BRAM Word[7:0]  = sample_data
```

## 2. 공통 명명 규칙

- Module: `lower_snake_case`
- Input: `_i`
- Output: `_o`
- Active-low input: `_ni`
- Parameter/localparam: `UPPER_SNAKE_CASE`
- Core clock/reset: `clk_i`, `rst_ni`
- AXI wrapper clock/reset: `s_axi_aclk`, `s_axi_aresetn`
- 모든 IP와 BRAM은 동일한 100 MHz clock을 사용한다.

## 3. IP 간 연결 Port

### 3.1 Probe Sampler core

| 방향 | 이름 | 폭 | 의미 |
|---|---|---:|---|
| input | `clk_i` | 1 | 100 MHz system clock |
| input | `rst_ni` | 1 | synchronous active-low reset |
| input | `probe_i` | 8 | 원본 probe 입력 |
| input | `enable_i` | 1 | sampler enable |
| input | `soft_clear_i` | 1 | 1-clock clear pulse |
| input | `divider_sel_i` | 2 | sample divider encoding |
| input | `channel_mask_i` | 8 | channel enable mask |
| output | `sample_data_o` | 8 | `probe_i & channel_mask_i` |
| output | `sample_valid_o` | 1 | 새 sample을 나타내는 1-clock pulse |
| output | `sample_count_o` | 32 | 누적 valid sample 수 |

Divider encoding은 다음 값으로 고정한다.

| `divider_sel_i` | Divider | Sample rate |
|---:|---:|---:|
| `2'b00` | 1 | 100 MS/s |
| `2'b01` | 2 | 50 MS/s |
| `2'b10` | 4 | 25 MS/s |
| `2'b11` | 8 | 12.5 MS/s |

### 3.2 Basic Trigger Engine core

| 방향 | 이름 | 폭 | 의미 |
|---|---|---:|---|
| input | `clk_i` | 1 | system clock |
| input | `rst_ni` | 1 | synchronous active-low reset |
| input | `sample_data_i` | 8 | Sampler의 현재 sample |
| input | `sample_valid_i` | 1 | 현재 sample valid |
| input | `arm_i` | 1 | 1-clock arm pulse |
| input | `clear_i` | 1 | 1-clock clear pulse |
| input | `mode_i` | 2 | disabled/rising/falling/pattern |
| input | `edge_channel_i` | 3 | edge trigger 대상 channel |
| input | `pattern_value_i` | 8 | pattern compare value |
| input | `pattern_mask_i` | 8 | pattern compare mask |
| output | `trigger_pulse_o` | 1 | 현재 sample에 대응하는 trigger |
| output | `armed_o` | 1 | trigger armed 상태 |
| output | `triggered_o` | 1 | trigger 발생 latch |
| output | `trigger_count_o` | 32 | 누적 trigger 횟수 |

Trigger mode encoding은 다음 값으로 고정한다.

| 값 | Mode |
|---:|---|
| `2'b00` | Disabled |
| `2'b01` | Rising edge |
| `2'b10` | Falling edge |
| `2'b11` | Masked pattern entry |

### 3.3 Circular Trace Buffer core

| 방향 | 이름 | 폭 | 의미 |
|---|---|---:|---|
| input | `clk_i` | 1 | system clock |
| input | `rst_ni` | 1 | synchronous active-low reset |
| input | `sample_data_i` | 8 | Sampler의 현재 sample |
| input | `sample_valid_i` | 1 | 현재 sample valid |
| input | `trigger_pulse_i` | 1 | 현재 sample에 대응하는 trigger |
| input | `arm_i` | 1 | 1-clock capture arm pulse |
| input | `clear_done_i` | 1 | 1-clock done/IRQ clear pulse |
| input | `abort_i` | 1 | 1-clock capture abort pulse |
| output | `busy_o` | 1 | capture 동작 중 |
| output | `pre_ready_o` | 1 | pre-trigger 512 samples 확보 |
| output | `triggered_o` | 1 | trigger 수신 latch |
| output | `capture_done_o` | 1 | capture 완료 latch |
| output | `irq_o` | 1 | 완료 level interrupt |
| output | `start_addr_o` | 10 | 시간순 첫 sample의 물리 word 주소 |
| output | `trigger_addr_o` | 10 | trigger sample의 물리 word 주소 |
| output | `write_addr_o` | 10 | 가장 최근에 쓴 물리 word 주소 |
| output | `bram_en_o` | 1 | BRAM Port A enable |
| output | `bram_we_o` | 4 | BRAM byte write enable |
| output | `bram_addr_o` | 10 | BRAM Port A word address |
| output | `bram_wdata_o` | 32 | `{24'b0, sample_data_i}` |

## 4. Sample과 Trigger 타이밍 계약

Sampler의 `sample_data_o`와 `sample_valid_o`는 Trigger Engine과 Trace Buffer에
동시에 연결한다.

```text
Probe Sampler.sample_data_o  ─┬─> Trigger Engine.sample_data_i
                              └─> Trace Buffer.sample_data_i

Probe Sampler.sample_valid_o ─┬─> Trigger Engine.sample_valid_i
                              └─> Trace Buffer.sample_valid_i

Trigger Engine.trigger_pulse_o ─> Trace Buffer.trigger_pulse_i
```

`trigger_pulse_o`는 `sample_valid_i=1`인 해당 cycle의 `sample_data_i`와 정렬되어야
한다. Trigger Engine은 registered pulse로 한 sample 늦추지 않는다. 권장 구현은
현재 sample과 저장된 이전 sample로 trigger 조건을 combinational 계산하고, 상태와
이전 sample만 clock edge에서 갱신하는 방식이다.

Trace Buffer는 `sample_valid_i=1`인 clock edge에서 다음을 동시에 수행한다.

1. 현재 `sample_data_i`를 현재 write pointer에 저장한다.
2. `trigger_pulse_i=1`이면 같은 주소를 `trigger_addr_o`로 latch한다.
3. 따라서 trigger가 판정된 현재 sample이 정확히 trigger sample이 된다.

Trigger Engine 정의:

```text
rising  = previous_sample[channel] == 0 && current_sample[channel] == 1
falling = previous_sample[channel] == 1 && current_sample[channel] == 0
match   = (current_sample & pattern_mask) ==
          (pattern_value  & pattern_mask)

pattern_trigger = match && !previous_match && pattern_mask != 0
```

- Trigger mode는 한 번에 하나만 활성화한다.
- `previous_sample`과 `previous_match`는 `sample_valid_i=1`일 때만 갱신한다.
- ARM 이후 첫 valid sample은 edge 비교 기준만 만들며 edge trigger를 내지 않는다.
- Pattern이 계속 유지돼도 진입 시 한 번만 trigger한다.
- Trigger 발생 후 Clear 전에는 추가 pulse를 생성하지 않는다.

### 4.1 시스템 ARM 순서

Trigger Engine은 one-shot이므로 Trace Buffer가 `PREFILL`인 동안 먼저 trigger되면
그 pulse는 Buffer에서 무시되고, Trigger Engine도 Clear 전에는 다시 pulse를 내지
않는다. 따라서 통합 소프트웨어는 다음 순서를 반드시 사용한다.

```text
1. Sampler Disable 및 설정
2. Trigger Engine Clear (아직 ARM하지 않음)
3. Trace Buffer Abort/Clear
4. Trace Buffer ARM
5. Sampler Enable
6. TRACE_STATUS.PRE_READY=1 poll
7. Trigger Engine Clear 후 ARM
8. TRACE_STATUS.DONE=1 대기
```

핵심 계약은 **Trace Buffer `PRE_READY=1`을 확인한 뒤 Trigger Engine을 ARM**하는
것이다. Buffer는 `ARMED`에서 Trigger를 기다리는 동안에도 circular write를
계속하므로 AXI polling/ARM 지연이 있어도 trigger 직전 512개 sample은 보존된다.

## 5. Circular Capture 정의

상태는 다음 다섯 개로 고정한다.

| 상태 | 동작 | 전이 |
|---|---|---|
| `IDLE` | write 정지, capture 대기 | `arm_i` → `PREFILL` |
| `PREFILL` | valid sample 512개 저장 | 512번째 저장 후 `ARMED` |
| `ARMED` | circular write, trigger 대기 | valid sample과 trigger 동시 발생 → `POST_CAPTURE` |
| `POST_CAPTURE` | trigger 이후 sample 저장 | post 총 512개 완료 → `DONE` |
| `DONE` | write 정지, done/IRQ 유지 | clear → `IDLE`, arm → 새 capture |

- `PREFILL` 중 trigger는 무시한다.
- 512번째 prefill sample과 동시에 들어온 trigger도 무시한다.
- `ARMED`에서 trigger가 들어온 sample을 post-trigger 1번째로 계산한다.
- 이후 valid sample 511개를 더 저장한다.
- 최종 논리 배열은 다음과 같다.

```text
Logical 0..511    : trigger 직전 512 samples
Logical 512       : trigger sample
Logical 513..1023 : trigger 이후 511 samples
```

마지막 post sample 저장과 동시에:

```text
start_addr   = (last_write_addr + 1) mod 1024
logical_addr = (start_addr + logical_index) mod 1024
trigger logical index = 512
```

`write_addr_o`는 가장 최근에 실제로 쓴 주소이다. 아직 아무 sample도 쓰지 않은
상태에서는 0을 반환한다.

제어 우선순위는 다음으로 고정한다.

```text
reset > abort > clear_done > arm > normal capture
```

- `abort_i`: 즉시 `IDLE`, 모든 상태 latch와 IRQ 해제, BRAM 내용은 유지
- `clear_done_i`: `DONE`에서 done/IRQ를 해제하고 `IDLE`로 이동
- `arm_i`: `IDLE` 또는 `DONE`에서 새 capture 시작, pointer/status 초기화
- busy 상태에서 추가 `arm_i`는 무시
- `irq_o`는 pulse가 아니라 `capture_done_o`와 같은 level이며 clear까지 유지

## 6. IP별 Register Map

각 IP는 별도의 AXI4-Lite base address를 가진다. 아래 offset은 각 IP base 기준의
32-bit little-endian byte offset이며 모두 4-byte aligned이다. Reserved bit는
write 시 무시하고 read 시 0을 반환한다.

이 Frozen v2.1 표가 원 기획서의 “권장 레지스터 맵”보다 우선한다. 특히 Trace
Buffer `CONTROL`은 저장형 R/W register가 아니라 W1P이며 read 값은 0이다.

### 6.1 Probe Sampler

| Offset | Register | 접근 | 정의 |
|---:|---|---|---|
| `0x00` | `CONTROL` | RW/W1P | `[0] ENABLE`, `[1] SOFT_CLEAR` |
| `0x04` | `CONFIG` | RW | `[1:0] DIVIDER_SEL`, `[15:8] CHANNEL_MASK` |
| `0x08` | `LAST_SAMPLE` | RO | `[7:0]` 최근 sample |
| `0x0C` | `SAMPLE_COUNT` | RO | `[31:0]` valid sample 누적 수 |

`ENABLE`은 저장되는 bit이고 `SOFT_CLEAR`는 write-one-pulse이며 read 시 0이다.

### 6.2 Basic Trigger Engine

| Offset | Register | 접근 | 정의 |
|---:|---|---|---|
| `0x00` | `CONTROL` | W1P | `[0] ARM`, `[1] CLEAR` |
| `0x04` | `CONFIG` | RW | `[1:0] MODE`, `[10:8] EDGE_CHANNEL` |
| `0x08` | `PATTERN` | RW | `[7:0] VALUE`, `[15:8] MASK` |
| `0x0C` | `STATUS` | RO | `[0] ARMED`, `[1] TRIGGERED` |
| `0x10` | `TRIGGER_COUNT` | RO | `[31:0]` 누적 trigger 횟수 |

### 6.3 Circular Trace Buffer

| Offset | Register | 접근 | 정의 |
|---:|---|---|---|
| `0x00` | `CONTROL` | W1P | `[0] ARM`, `[1] CLEAR_DONE`, `[2] ABORT` |
| `0x04` | `STATUS` | RO | `[0] BUSY`, `[1] PRE_READY`, `[2] TRIGGERED`, `[3] DONE` |
| `0x08` | `START_ADDR` | RO | `[9:0]` 시간순 첫 sample word 주소 |
| `0x0C` | `TRIGGER_ADDR` | RO | `[9:0]` trigger sample word 주소 |
| `0x10` | `WRITE_ADDR` | RO | `[9:0]` 가장 최근 write word 주소 |
| `0x14` | `CAPTURE_INFO` | RO | `[10:0] DEPTH=1024`, `[25:16] TRIGGER_INDEX=512` |

W1P register는 write된 AXI transaction에서만 1-clock pulse를 만들고, read 시 0을
반환한다.

## 7. BRAM 및 주소 규칙

Block Memory Generator는 true dual-port, 1,024 × 32-bit로 구성한다.

| Port | 연결 | 용도 |
|---|---|---|
| Port A | Circular Trace Buffer native interface | capture write |
| Port B | AXI BRAM Controller | MicroBlaze read |

- Port A word address 폭은 10-bit이며 범위는 0..1023이다.
- MicroBlaze의 AXI 주소는 byte address이므로 capture memory range는 4 KiB이다.
- CPU에서 word index `i`의 주소는 `BRAM_BASE + i * 4`이다.
- C에서는 `volatile uint32_t *trace_mem`에 대해 `trace_mem[i]`로 접근한다.
- 두 port는 동일한 100 MHz clock을 사용한다.
- Capture 중 CPU read 동작은 보장 대상이 아니다. `DONE=1` 이후 읽는다.
- 합성 후 capture memory가 LUTRAM이 아닌 BRAM으로 구현됐는지 확인한다.

시간순 CPU read:

```c
uint32_t start =
    Xil_In32(TRACE_BASEADDR + TRACE_REG_START_ADDR) & TRACE_ADDR_MASK;

for (uint32_t i = 0; i < 1024u; ++i) {
    uint32_t physical = (start + i) & 0x3FFu;
    uint8_t sample = (uint8_t)(trace_mem[physical] & 0xFFu);
}
```

여기서 `TRACE_BASEADDR`는 Vivado Address Editor가 Trace Buffer AXI4-Lite
register 영역에 배정한 base address이다.

### 7.1 Core와 Packaged IP의 BRAM Port

Core의 10-bit word index는 Vivado 표준 BRAM master interface에 맞추기 위해
packaged top에서 32-bit byte address로 변환한다.

| 구분 | Core Port | Packaged IP Port | 의미 |
|---|---|---|---|
| Address | `bram_addr_o[9:0]` | `bram_addr_o[31:0]` | `packaged = core_word_index << 2` |
| Write data | `bram_wdata_o[31:0]` | `bram_wrdata_o[31:0]` | 같은 32-bit sample word |
| Write enable | `bram_we_o[3:0]` | `bram_we_o[3:0]` | full-word write 시 `4'b1111` |
| Enable | `bram_en_o` | `bram_en_o` | valid sample write enable |

Packaged IP의 `BRAM_PORTA` interface metadata도 byte address, 32-bit width,
4,096-byte size로 고정한다.

## 8. 팀별 구현 경계

| 담당 | 소유 IP | 반드시 제공할 신호/산출물 |
|---|---|---|
| 국승호 | Probe Sampler | `sample_data_o`, `sample_valid_o`, Divider/Mask, AXI wrapper, TB |
| 김도근 | Trigger Engine | 같은-sample `trigger_pulse_o`, mode/pattern, AXI wrapper, TB, C header 반영 |
| 윤형욱 | Circular Trace Buffer | FSM, BRAM Port A, 주소/status/IRQ, AXI wrapper, wrap TB |

공통 통합 전 각 담당자는 다음을 확인한다.

- Port 이름과 bit 폭이 이 문서와 일치한다.
- Register offset과 bit field가 이 문서와 일치한다.
- Reset polarity가 active-low로 일치한다.
- `sample_valid`가 없을 때 sample 관련 상태를 갱신하지 않는다.
- Reserved bit read 값은 0이다.

## 9. 변경 관리

이 문서는 Frozen v2.1이다. Port, register, trigger sample 의미, BRAM 규격을 변경할
때는 세 팀원이 합의하고 다음 파일을 같은 commit에서 함께 갱신한다.

- `docs/day1_common_spec.md`
- `rtl/include/logic_analyzer_pkg.sv`
- `sw/include/logic_analyzer_regs.h`
