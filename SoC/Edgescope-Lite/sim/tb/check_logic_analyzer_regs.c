#include "logic_analyzer_regs.h"

_Static_assert(EDGE_SCOPE_SPEC_VERSION_MAJOR == 2u, "spec major");
_Static_assert(EDGE_SCOPE_SPEC_VERSION_MINOR == 1u, "spec minor");

_Static_assert(TRACE_REG_CONTROL == 0x00u, "TRACE CONTROL offset");
_Static_assert(TRACE_REG_STATUS == 0x04u, "TRACE STATUS offset");
_Static_assert(TRACE_REG_START_ADDR == 0x08u, "TRACE START offset");
_Static_assert(TRACE_REG_TRIGGER_ADDR == 0x0Cu, "TRACE TRIGGER offset");
_Static_assert(TRACE_REG_WRITE_ADDR == 0x10u, "TRACE WRITE offset");
_Static_assert(TRACE_REG_CAPTURE_INFO == 0x14u, "TRACE INFO offset");

_Static_assert(TRACE_CONTROL_ARM == (1u << 0), "ARM bit");
_Static_assert(TRACE_CONTROL_CLEAR_DONE == (1u << 1), "CLEAR bit");
_Static_assert(TRACE_CONTROL_ABORT == (1u << 2), "ABORT bit");
_Static_assert(TRACE_STATUS_DONE == (1u << 3), "DONE bit");

_Static_assert(EDGE_SCOPE_BRAM_WORD_BITS == 32u, "BRAM width");
_Static_assert(EDGE_SCOPE_CAPTURE_DEPTH == 1024u, "capture depth");
_Static_assert(EDGE_SCOPE_CAPTURE_BYTES == 4096u, "capture bytes");
_Static_assert(EDGE_SCOPE_PRE_SAMPLES == 512u, "pre-trigger count");
_Static_assert(EDGE_SCOPE_POST_SAMPLES == 512u, "post-trigger count");
_Static_assert(EDGE_SCOPE_TRIGGER_INDEX == 512u, "trigger index");

_Static_assert(
    ((EDGE_SCOPE_CAPTURE_DEPTH & TRACE_CAPTURE_INFO_DEPTH_MASK) |
     ((EDGE_SCOPE_TRIGGER_INDEX << TRACE_CAPTURE_INFO_TRIG_SHIFT) &
      TRACE_CAPTURE_INFO_TRIG_MASK)) == 0x02000400u,
    "CAPTURE_INFO encoding");

int main(void)
{
    return 0;
}
