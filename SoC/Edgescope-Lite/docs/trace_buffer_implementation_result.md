# Circular Trace Buffer 구현 결과

검증일: 2026-07-27  
Tool: Vivado 2024.2  
Part: `xc7a35tcpg236-1`  
Clock constraint: 10.000 ns (100 MHz)

## Packaged IP

| 항목 | 결과 |
|---|---|
| VLNV | `user.org:user:circular_trace_buffer:1.0` |
| AXI interface | `s_axi`, AXI4-Lite slave |
| BRAM interface | `BRAM_PORTA`, BRAM master |
| BRAM metadata | byte address, 32-bit, 4,096 bytes |
| Interrupt | `irq`, active-high level interface (`irq_o`) |
| IP integrity check | PASS |
| Catalog load | PASS |
| Block Design validation | PASS |

IP repository:

```text
ip_repo/circular_trace_buffer_1_0
```

## Routed OOC 결과

| 지표 | 결과 |
|---|---:|
| Slice LUT | 73 |
| Slice Register | 90 |
| BRAM | 0 |
| DSP | 0 |
| WNS | +4.978 ns |
| WHS | +0.170 ns |
| TNS | 0.000 ns |
| THS | 0.000 ns |
| Failing setup endpoints | 0 |
| Failing hold endpoints | 0 |
| Routed nets | 140 / 140 |

BRAM은 별도 `capture_bram` Catalog IP이므로 위 Custom IP 자원에는 포함되지 않는다.
전체 capture hardware 기준으로는 RAMB36E1 1개가 추가된다.

AXI BRAM Controller까지 포함한 packaged subsystem 합성 결과는 338 LUT, 306 FF,
RAMB36E1 1개, DSP 0개다. BD parameter propagation 후 BMG
`C_WRITE_DEPTH_A/B=1024`, `MEM_SIZE=4096`, `C_COMMON_CLK=1`을 확인했다.

## RTL 회귀

```bash
./scripts/run_regression.sh --waves
```

7개 SystemVerilog test와 C register-header `_Static_assert`가 모두 PASS했다.
AXI B/R back-pressure, partial AW/W reset, PREFILL trigger 무시, packaged top의
BRAM clock/reset/address 경로도 포함한다.

## 재현 명령

```bash
/media/user4/data/tools/Vivado/2024.2/bin/vivado \
  -mode batch -source scripts/package_trace_buffer_ip.tcl

/media/user4/data/tools/Vivado/2024.2/bin/vivado \
  -mode batch -source scripts/synth_trace_buffer_ip.tcl

/media/user4/data/tools/Vivado/2024.2/bin/vivado \
  -mode batch -source scripts/validate_packaged_ip_bd.tcl
```

최종 MicroBlaze 전체 Block Design에서는 시스템 implementation report로 WNS와
자원을 다시 확인해야 한다. 위 timing은 interface I/O delay가 아닌 Custom IP
내부 OOC setup/hold 결과다.
