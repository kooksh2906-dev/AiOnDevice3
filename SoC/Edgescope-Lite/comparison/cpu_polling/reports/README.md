# Implementation reports

Vivado 2024.2에서 CPU Polling Resource Build를 Implementation까지 완료하고
`../hw/export_reports.tcl`로 생성한 보고서다.

생성 대상:

- `utilization.rpt`
- `hierarchical_utilization.rpt`
- `timing_summary.rpt`
- `drc.rpt`

최종 구현 결과:

- Timing met: WNS `+0.939 ns`, TNS `0.000 ns`
- Hold met: WHS `+0.047 ns`, THS `0.000 ns`
- Slice LUTs: `2,782 / 20,800` (`13.38%`)
- Slice Registers: `2,560 / 41,600` (`6.15%`)
- Block RAM Tile: `32 / 50` (`64.00%`)
- DSPs: `0 / 90`
- DRC Errors: `0`
- DRC Warnings: `3` (`CFGBVS-1`, `PDRC-134`, `PDRC-136`)

Resource Build에는 ILA, EdgeScope Custom IP, Capture BRAM을 넣지 않았다. 이
보고서는 구현 결과이며 실제 보드 Polling 속도와 Trigger/Pulse 시험 결과를
대신하지 않는다.
