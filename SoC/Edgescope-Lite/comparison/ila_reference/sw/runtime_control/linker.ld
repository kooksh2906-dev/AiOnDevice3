/*
 * Step 6 runtime-control firmware memory layout.
 *
 * The comparison SoC maps both the MicroBlaze RISC-V instruction and data
 * local-memory ports to the same 128 KiB BRAM at 0x0000_0000.
 */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
  BRAM (rwx) : ORIGIN = 0x00000000, LENGTH = 0x00020000
}

PHDRS
{
  text PT_LOAD FLAGS(5); /* Read + Execute */
  data PT_LOAD FLAGS(6); /* Read + Write */
}

SECTIONS
{
  .vectors ORIGIN(BRAM) : ALIGN(4)
  {
    KEEP(*(.vectors))
  } > BRAM :text

  .text : ALIGN(4)
  {
    *(.text .text.*)
  } > BRAM :text

  .rodata : ALIGN(4)
  {
    *(.rodata .rodata.*)
  } > BRAM :text

  .data : ALIGN(4)
  {
    __data_start = .;
    *(.data .data.*)
    *(.sdata .sdata.*)
    __data_end = .;
  } > BRAM :data

  .bss (NOLOAD) : ALIGN(4)
  {
    __bss_start = .;
    *(.bss .bss.*)
    *(.sbss .sbss.*)
    *(COMMON)
    . = ALIGN(4);
    __bss_end = .;
  } > BRAM :data

  __image_end = .;
  __stack_bottom = ORIGIN(BRAM) + LENGTH(BRAM) - 0x2000;
  __stack_top = ORIGIN(BRAM) + LENGTH(BRAM);

  ASSERT(__image_end <= __stack_bottom,
         "Runtime image overlaps the reserved 8 KiB stack")

  /DISCARD/ :
  {
    *(.comment)
    *(.note.gnu.build-id)
    *(.eh_frame .eh_frame.*)
  }
}
