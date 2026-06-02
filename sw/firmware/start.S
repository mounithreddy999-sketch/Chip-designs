.section .text.init
.global _start
_start:
    /* Initialize stack pointer */
    la sp, _sp
    /* Call main C function */
    call main
    /* Loop forever if main returns */
1:  j 1b
