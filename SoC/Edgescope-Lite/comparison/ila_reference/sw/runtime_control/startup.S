/*
 * Minimal reset entry for the Step 6 MicroBlaze RISC-V runtime.
 *
 * The image is linked at address 0 and runs entirely from the 128 KiB
 * ILMB/DLMB local BRAM.  No C runtime or standard library is required.
 */

    .section .vectors, "ax", @progbits
    .align  2
    .globl  _start
    .type   _start, @function
_start:
    /* Keep asynchronous interrupts disabled; this firmware polls peripherals. */
    csrci   mstatus, 8

    /* Give unexpected traps a deterministic local handler. */
    la      t0, _trap_entry
    csrw    mtvec, t0

    la      sp, __stack_top

    /* The ELF loader initializes .data.  Clear the NOLOAD .bss explicitly. */
    la      t0, __bss_start
    la      t1, __bss_end
.Lbss_loop:
    bgeu    t0, t1, .Lbss_done
    sw      zero, 0(t0)
    addi    t0, t0, 4
    j       .Lbss_loop
.Lbss_done:
    call    main

    /* main() is not expected to return. */
.Lhalt:
    j       .Lhalt
    .size   _start, . - _start

    .align  2
    .globl  _trap_entry
    .type   _trap_entry, @function
_trap_entry:
    /* Do not restart a possibly destructive command after a fault. */
    j       _trap_entry
    .size   _trap_entry, . - _trap_entry

    .section .note.GNU-stack, "", @progbits
