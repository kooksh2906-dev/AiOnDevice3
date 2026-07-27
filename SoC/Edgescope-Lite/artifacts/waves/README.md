# Simulation Waveforms

`scripts/run_regression.sh --waves`로 생성한 실제 회귀 테스트 VCD이다.

발표용 핵심 파일:

- `tb_circular_trace_buffer_trigger.vcd`: 512:512 capture, trigger index 512,
  DONE 이후 write 정지
- `tb_circular_trace_buffer_wrap.vcd`: trigger physical address
  0/1/1022/1023 wrap-around
- `tb_circular_trace_buffer_bram.vcd`: packaged top, 32-bit byte address,
  Port B logical-order read

GTKWave 또는 Vivado Simulator에서 다음 신호를 우선 표시한다.

```text
sample_valid_i
trigger_pulse_i
dut.state_q / u_trace.u_axi.u_core.state_q
pre_ready_o
triggered_o
capture_done_o
irq_o
bram_en_o / bram_en
bram_addr_o / bram_byte_addr_a
start_addr_o
trigger_addr_o
write_addr_o
```

VCD는 RTL에서 생성한 검증 원본이며 `docs/circular_trace_buffer_waveform.png`는
발표 슬라이드에 바로 넣을 수 있도록 핵심 구간을 요약한 도식이다.
