# Frozen ILA Evidence Sources

This directory preserves the exact common Base SoC and Test Pattern Generator
sources used to create the checksum-bound ILA Steps 3–10 evidence.

The portable sources under `comparison/common/` may evolve for board discovery
or rebuild convenience. They must not silently change the provenance of an
already measured hardware result. ILA rebuild scripts and the Step 9 validator
therefore use this frozen copy.

Expected SHA-256 values:

```text
base_soc.tcl                              31f6d77d2150d0d6a744fae02b2a85661340fb71a17906ca5267ab8a74ae078c
add_test_pattern_generator.tcl            971cf1b87e4b39b522626746e5d3464e840a4f413d183e8db6e353587f2121d8
rtl/test_pattern_generator.sv             9f0a1b7f9a54ddc8f9eb3e093382af9eb6a6cdf8c9ab48ab4ce65d83e7eb5440
rtl/test_pattern_generator_gpio_adapter.v 73fd657010c8109d5a1c7e5168d4ae4a4d576fc80e2ddd02978b087523249580
```

To create a new official measurement from an updated portable Base SoC, replace
this snapshot intentionally and regenerate all routed, hardware, Step 9, and
Step 10 evidence together.
