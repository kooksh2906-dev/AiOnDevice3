# Vitis build

After the Vivado C build has exported its XSA, bitstream, MMI, and LTX, run:

```bash
vitis -s comparison/vivado_ila/vitis/build_vivado_ila.py
```

When starting both builds in parallel, the script can wait for the hardware
inputs:

```bash
vitis -s comparison/vivado_ila/vitis/build_vivado_ila.py --wait-xsa 1800
```

Successful output is copied to:

- `comparison/vivado_ila/vitis_artifacts/vivado_ila_app.elf`
- `comparison/vivado_ila/vitis_artifacts/vivado_ila_app.bit`

The bit file is generated with `updatemem`, so the MicroBlaze application is
already initialized in local BRAM. Program it and associate the ILA probes
with:

```bash
vivado -mode batch \
  -source comparison/vivado_ila/vitis/program_bitstream.tcl
```
