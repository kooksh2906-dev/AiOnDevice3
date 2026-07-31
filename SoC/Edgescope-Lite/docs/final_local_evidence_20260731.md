# Final Local Evidence Backup

This backup preserves the final artifacts that existed only on the Ubuntu
demonstration workstation as of 2026-07-31.

## Runtime fixes

- `scripts/cpu_polling_gui.py`
  - Rebuilds the Vivado ILA capture configuration and validation result after a
    measured CSV is imported.
- `comparison/vivado_ila/hw/capture_ila.tcl`
  - Accepts a read-only ILA run-control property only when its current value
    already matches the requested value.

## Measured Vivado ILA captures

`comparison/vivado_ila/results/captures/` contains ten raw JTAG CSV captures:

- four rising-edge captures
- three falling-edge captures
- three pattern captures

These files are preserved as measured evidence and are not simulated examples.

## Routed implementation evidence

| Design | Routed checkpoint | Power report | Dynamic power |
|---|---|---|---:|
| B — EdgeScope-Lite | `comparison/edgescope_lite/reports/edgescope_lite_routed.dcp` | `comparison/edgescope_lite/reports/power.rpt` | 0.135 W |
| C — Vivado ILA | `comparison/vivado_ila/reports/vivado_ila_routed.dcp` | `comparison/vivado_ila/reports/power.rpt` | 0.142 W |

Both reports were produced from routed Vivado 2024.2 implementations. The
reported dynamic-power reduction of Design B relative to Design C is about
4.9%.

## Personal handoff documents

- `(gemini)easy_trace_buffer_concept.md`
- `yoon_hyungwook_essential_concepts.md`
- `yoon_hyungwook_day1_notion.md`
- `yoon_hyungwook_day2_notion.md`
