# 윤형욱 Circular Trace Buffer 인수인계

## 팀에 전달할 필수 파일

| 용도 | 파일 |
|---|---|
| 공통 계약 | `docs/day1_common_spec.md` (Frozen v2.1) |
| RTL 상수 | `rtl/include/logic_analyzer_pkg.sv` |
| Vitis 상수 | `sw/include/logic_analyzer_regs.h` |
| Vivado IP repository | `ip_repo/circular_trace_buffer_1_0/` |
| BRAM/통합 재현 | `scripts/create_capture_bram.tcl`, `scripts/validate_packaged_ip_bd.tcl` |
| 검증 | `scripts/run_regression.sh`, `docs/verification_report.md` |

## Vivado Block Design 연결

1. IP repository에 `ip_repo/`를 추가하고
   `user.org:user:circular_trace_buffer:1.0`을 배치한다.
2. BMG는 true dual port, 32-bit × 1024, byte write enable, common clock으로 둔다.
3. Trace `BRAM_PORTA` → BMG `BRAM_PORTA`를 연결한다.
4. AXI BRAM Controller `BRAM_PORTA` → BMG `BRAM_PORTB`를 연결한다.
5. Trace `s_axi`와 AXI BRAM Controller `S_AXI`를 SmartConnect에 연결한다.
6. Trace, AXI BRAM Controller, BMG 두 port를 같은 100 MHz clock에 둔다.
7. Trace register와 capture memory에 각각 4 KiB address range를 배정한다.
8. `irq`는 AXI Interrupt Controller/Concat에 연결하거나 최초 통합에서는
   `STATUS.DONE` polling을 사용한다.

검증 후 BMG property가 아래와 같은지 확인한다.

```text
Write_Depth_A = 1024
Write_Width_A = 32
MEM_SIZE Port A/B = 4096
Assume_Synchronous_Clk = true
```

## 필수 소프트웨어 순서

```c
/* Base address names are placeholders for the final xparameters.h names. */
Xil_Out32(TRIGGER_BASEADDR + TRIGGER_REG_CONTROL,
          TRIGGER_CONTROL_CLEAR);
Xil_Out32(TRACE_BASEADDR + TRACE_REG_CONTROL,
          TRACE_CONTROL_ABORT);
Xil_Out32(TRACE_BASEADDR + TRACE_REG_CONTROL,
          TRACE_CONTROL_ARM);

/* Enable the configured Sampler here. */

while ((Xil_In32(TRACE_BASEADDR + TRACE_REG_STATUS) &
        TRACE_STATUS_PRE_READY) == 0u) {
}

/* The Trigger must only be armed after PRE_READY. */
Xil_Out32(TRIGGER_BASEADDR + TRIGGER_REG_CONTROL,
          TRIGGER_CONTROL_CLEAR);
Xil_Out32(TRIGGER_BASEADDR + TRIGGER_REG_CONTROL,
          TRIGGER_CONTROL_ARM);

while ((Xil_In32(TRACE_BASEADDR + TRACE_REG_STATUS) &
        TRACE_STATUS_DONE) == 0u) {
    /* Add AXI Timer or software timeout, then issue TRACE_CONTROL_ABORT. */
}
```

완료 후 시간순 read:

```c
uint32_t start =
    Xil_In32(TRACE_BASEADDR + TRACE_REG_START_ADDR) & TRACE_ADDR_MASK;
volatile uint32_t *trace_mem =
    (volatile uint32_t *)CAPTURE_BRAM_BASEADDR;

for (uint32_t i = 0; i < EDGE_SCOPE_CAPTURE_DEPTH; ++i) {
    uint32_t physical = (start + i) & TRACE_ADDR_MASK;
    uint8_t sample = (uint8_t)(trace_mem[physical] & 0xFFu);
    /* UART output: logical index i, sample */
}
```

## 재현 명령

```bash
./scripts/run_regression.sh --waves

/media/user4/data/tools/Vivado/2024.2/bin/vivado \
  -mode batch -source scripts/package_trace_buffer_ip.tcl

/media/user4/data/tools/Vivado/2024.2/bin/vivado \
  -mode batch -source scripts/synth_trace_buffer_ip.tcl

/media/user4/data/tools/Vivado/2024.2/bin/vivado \
  -mode batch -source scripts/validate_packaged_ip_bd.tcl
```

## 통합 완료 체크

- [ ] `PRE_READY` 확인 후 Trigger ARM
- [ ] `DONE=1`, `irq=1`, 이후 Port A write 없음
- [ ] `physical(512) == TRIGGER_ADDR`
- [ ] Port B에서 1,024개 시간순 read
- [ ] BMG depth 1024, RAMB36E1 1개
- [ ] 최종 전체 BD setup/hold timing PASS

