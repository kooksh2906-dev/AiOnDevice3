# Step 9 common Base+Generator comparison baseline.
#
# Keep the otherwise-unconnected Generator output logic from being trimmed so
# the same common Generator hierarchy is present in the CPU, ILA, Custom, and
# baseline builds.  This constraint adds no probe sink or debug core.

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

set_property DONT_TOUCH true \
  [get_cells -hier -quiet *test_pattern_generator_gpio_adapter_0]
