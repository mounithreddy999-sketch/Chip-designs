MEMORY {
    RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 64K
}

SECTIONS {
    .text : {
        *(.text.init)
        *(.text)
        *(.rodata)
        *(.srodata)
    } > RAM

    .data : {
        *(.data)
        *(.sdata)
    } > RAM

    .bss : {
        *(.bss)
        *(.sbss)
        *(COMMON)
    } > RAM

    .stack (NOLOAD) : {
        . = ALIGN(16);
        . = . + 4K;
        _sp = .;
    } > RAM
}
