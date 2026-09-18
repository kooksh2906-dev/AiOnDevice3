# Vivado ILA generator-control firmware

This MicroBlaze application controls only the common deterministic test
generator. Vivado captures the eight probe bits through JTAG and exports the
ILA samples as CSV; the firmware intentionally emits no sample dump over UART.

## UART protocol

The serial link is `9600,8-N-1`. After reset the application emits:

```text
VIVADO_ILA_REFERENCE_READY
ANALYZER=VIVADO_ILA
SAMPLE_HZ=100000000
CAPTURE_DEPTH=1024
TRIGGER_INDEX=512
CAPTURE_TRANSPORT=VIVADO_JTAG_CSV
UART_SAMPLE_DUMP=DISABLED
```

Arm the Vivado ILA first, then send exactly one generator command:

| Command | Generator event | Expected ILA trigger |
|---|---|---|
| `r` | CH0 rising | yes |
| `f` | CH0 falling | yes |
| `p` | `0x95` to `0xA5` masked pattern | yes |
| `h` | masked pattern held after the event | yes |
| `z` | constant no-trigger interval | no |
| `u100` | one CH0 pulse, 100 sample-clock cycles wide | yes |

Terminate commands with CR or LF. Pulse command syntax is
`u<CYCLES><LF>`, where `CYCLES` is decimal `1..1048575`. Every accepted
command produces one `ILA_TRIAL_BEGIN` line before the generator starts and
one `ILA_TRIAL_COMPLETE` line after it finishes. `GENERATOR_DONE=1` confirms
stimulus completion, not ILA capture success; the host must verify the Vivado
capture separately.
