# Capture BRAM 통합

## 고정 구성

Block Memory Generator `capture_bram`:

| 설정 | 값 |
|---|---|
| Interface | Native |
| Memory type | True Dual Port RAM |
| Width/depth | 32-bit × 1,024 |
| Address mode | 32-bit byte address |
| BRAM interface memory size | 4,096 bytes |
| Byte write enable | 사용, byte size 8 |
| Port A | Circular Trace Buffer write |
| Port B | AXI BRAM Controller read |
| Clock | 두 port 모두 100 MHz |
| Output register | 비활성, synchronous read 1 cycle |

`scripts/create_capture_bram.tcl`을 Vivado 2024.2 batch mode로 실행하면 XCI와
out-of-context synthesis 결과를 생성한다.

```bash
/media/user4/data/tools/Vivado/2024.2/bin/vivado \
  -mode batch \
  -source scripts/create_capture_bram.tcl
```

## Port A 연결

Core가 내보내는 주소는 10-bit word index이고 BMG의 32-bit 주소는 byte
address이다.

```text
BMG addra = {20'b0, bram_addr_o[9:0], 2'b00}
```

| Trace Buffer | BMG Port A |
|---|---|
| `s_axi_aclk` | `clka` |
| `bram_en_o` | `ena` |
| `bram_we_o[3:0]` | `wea[3:0]` |
| adapter의 `byte_addr_o[31:0]` | `addra[31:0]` |
| `bram_wdata_o[31:0]` | `dina[31:0]` |

주소 변환에는 `rtl/top/capture_bram_addr_adapter.sv`를 사용한다.

## Port B와 AXI BRAM Controller

1. AXI BRAM Controller를 Single Port BRAM으로 설정한다.
2. Controller의 BRAM interface를 `capture_bram` Port B에 연결한다.
3. `S_AXI`는 MicroBlaze SmartConnect에 연결한다.
4. `s_axi_aclk`과 BMG `clkb`를 같은 100 MHz clock에 연결한다.
5. Address Editor에서 capture memory에 4 KiB range를 배정한다.
6. 최초 통합에서는 `STATUS.DONE=1`을 확인한 뒤 BRAM을 읽는다.

`BRAM_PORTA`와 `BRAM_PORTB`의 interface metadata `MEM_SIZE`는 둘 다 4096으로
유지한다. 외부화된 BRAM interface의 기본값 8192를 그대로 두면 Block Automation
propagation 과정에서 BMG depth가 2048로 바뀔 수 있다. 제공 Tcl script는 이를
명시적으로 4096으로 고정한다.

AXI BRAM Controller는 4 KiB 영역에 대해 12-bit byte address를 내보내고 BMG는
32-bit address port를 사용한다. BD 생성 시 “lower order bits will be connected”
width warning이 표시될 수 있으며, 상위 주소가 0인 이 구성에서는 정상이다.

CPU 주소 계산:

```text
byte_address = CAPTURE_BRAM_BASE + physical_word_index * 4
```

```c
volatile uint32_t *trace_mem =
    (volatile uint32_t *)XPAR_AXI_BRAM_CTRL_0_S_AXI_BASEADDR;

uint32_t word = trace_mem[physical_word_index];
uint8_t sample = (uint8_t)(word & 0xFFu);
```

CPU가 Port B에 write하지 않도록 소프트웨어에서 read-only memory로 취급한다.

## 검증 결과

Vivado 2024.2, `xc7a35tcpg236-1` out-of-context synthesis:

| Resource | 사용량 |
|---|---:|
| RAMB36E1 | 1 |
| Slice LUT | 0 |
| Slice Register | 0 |

`scripts/create_bram_subsystem_bd.tcl`로 AXI BRAM Controller와 BMG Port B 연결,
4 KiB address segment 및 100 MHz clock/reset을 재현할 수 있다.

`scripts/validate_packaged_ip_bd.tcl`의 통합 합성 결과:

| Resource | Trace + BMG + AXI BRAM Controller |
|---|---:|
| Slice LUT | 338 |
| Slice Register | 306 |
| RAMB36E1 | 1 |
| DSP | 0 |

Script는 BD validation 뒤 propagated depth가 1024인지, 합성 netlist의
RAMB36E1이 정확히 1개인지 자동으로 검사한다.
