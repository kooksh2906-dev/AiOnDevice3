# Step 5 implementation-only constraints for the automatically inserted
# Vivado Debug Hub.
#
# The ILA and Debug Hub are driven by the Clocking Wizard's 100 MHz output.
# Vivado 2024.2 may otherwise retain a 300 MHz metadata default for the
# automatically inserted Debug Hub.  Keep the metadata equal to the actual
# 10.000 ns clock so Hardware Manager selects a valid JTAG/debug clock ratio.

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

set_property C_CLK_INPUT_FREQ_HZ 100000000 \
  [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false \
  [get_debug_cores dbg_hub]
