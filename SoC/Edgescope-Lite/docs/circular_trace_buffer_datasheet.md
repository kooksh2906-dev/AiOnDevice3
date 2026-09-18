# EdgeScope Circular Trace Buffer IP — 1-Page Datasheet

Owner: 윤형욱 · IP version: 1.0 · Common specification: Frozen v2.1  
Target: Basys3 `xc7a35tcpg236-1` · Clock: 100 MHz · RTL: SystemVerilog

## Function

8-bit valid samples를 1,024 × 32-bit true dual-port BRAM에 circular write하고,
trigger 직전 512개와 trigger를 포함한 이후 512개를 보존한다. Capture 완료 시
주소/status와 active-high level interrupt를 제공한다.

| 고정 항목 | 값 |
|---|---:|
| Probe / BRAM word | 8-bit / 32-bit (`{24'b0, sample}`) |
| Physical word address | 10-bit, 0..1023 |
| Capture memory | 4,096 bytes |
| Logical trigger index | 512 |
| Reset | synchronous active-low |
| AXI4-Lite | 32-bit data, 6-bit local byte address |

## Capture Contract

```text
IDLE --ARM--> PREFILL --512 valid--> ARMED --valid+trigger-->
POST_CAPTURE --post total 512--> DONE --CLEAR_DONE--> IDLE
```

- `PREFILL` trigger와 512번째 prefill sample의 trigger는 무시한다.
- `ARMED`에서 trigger가 정렬된 sample을 BRAM에 쓰고 post sample #1로 센다.
- 이후 511개를 더 저장한 뒤 write를 멈추고 Done/IRQ를 유지한다.
- `START_ADDR = (last_write_addr + 1) mod 1024`
- `physical(i) = (START_ADDR + i) mod 1024`
- `physical(512) = TRIGGER_ADDR`
- 우선순위: `reset > abort > clear_done > arm > capture`

## Core Data/BRAM Interface

| Port | 방향/폭 | 의미 |
|---|---|---|
| `sample_data_i` | I/8 | 현재 sample |
| `sample_valid_i` | I/1 | sample write enable pulse |
| `trigger_pulse_i` | I/1 | 현재 sample과 정렬된 trigger |
| `busy_o`, `pre_ready_o` | O/1 | capture 중 / prefill 완료 |
| `triggered_o`, `capture_done_o`, `irq_o` | O/1 | latched status |
| `start_addr_o`, `trigger_addr_o`, `write_addr_o` | O/10 | physical word 주소 |
| `bram_en_o`, `bram_we_o[3:0]` | O | Native Port A control |
| `bram_addr_o[9:0]`, `bram_wdata_o[31:0]` | O | core word address/data |

Packaged IP `BRAM_PORTA`에서는 주소를
`bram_addr_o[31:0] = core_word_addr << 2`로 변환하고 write data 이름을
`bram_wrdata_o[31:0]`로 제공한다. Interface metadata는
`BYTE_ADDRESS`, `MEM_WIDTH=32`, `MEM_SIZE=4096`이다.

## AXI4-Lite Register Map

| Offset | Register | Access | Bits |
|---:|---|---|---|
| `0x00` | CONTROL | W1P/RO=0 | `[0] ARM [1] CLEAR_DONE [2] ABORT` |
| `0x04` | STATUS | RO | `[0] BUSY [1] PRE_READY [2] TRIGGERED [3] DONE` |
| `0x08` | START_ADDR | RO | `[9:0]` oldest retained sample |
| `0x0C` | TRIGGER_ADDR | RO | `[9:0]` trigger sample |
| `0x10` | WRITE_ADDR | RO | `[9:0]` last written sample |
| `0x14` | CAPTURE_INFO | RO | `[10:0]=1024`, `[25:16]=512` |

## Mandatory Integration Order

```text
Trigger Clear → Buffer ARM → Sampler Enable → PRE_READY poll
→ Trigger Clear/ARM → DONE poll/IRQ → BRAM Port B read
```

Trigger Engine을 `PRE_READY` 전에 ARM하면 one-shot trigger가 PREFILL 중 소진될
수 있다. CPU는 `DONE=1` 이후 Port B를 read-only로 사용한다.

## Verified Results

| 검증 | 결과 |
|---|---:|
| RTL/AXI/BRAM regression | 7 SV tests + C header check PASS |
| Boundary trigger | physical 0, 1, 1022, 1023 PASS |
| Packaged-IP/BD integrity | PASS |
| Custom IP routed OOC | 73 LUT, 90 FF |
| 100 MHz timing | Setup `+4.978 ns`, Hold `+0.170 ns` |
| Integrated Trace+BMG+AXI BRAM Controller | 338 LUT, 306 FF, 1 RAMB36E1, 0 DSP |

Waveform: [circular_trace_buffer_waveform.png](circular_trace_buffer_waveform.png)

