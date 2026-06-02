#include <stdint.h>

void main() {
    volatile uint32_t* cgra_base = (volatile uint32_t*) 0x40000000;
    volatile uint32_t* test_base = (volatile uint32_t*) 0x80000000;

    // 1. Program Instructions
    cgra_base[0x0] = 0x00000220; // Lower 32 bits
    cgra_base[0x4] = 0x00000280; // Upper 32 bits
    cgra_base[0x8] = 0x00000285; // Lower 32 bits
    cgra_base[0xC] = 0x00000280; // Upper 32 bits
    cgra_base[0x10] = 0x00000285; // Lower 32 bits
    cgra_base[0x14] = 0x00000280; // Upper 32 bits

    // 2. Write input boundary data
    cgra_base[0x104/4] = 5; // North (Activations)
    cgra_base[0x110/4] = 3; // West (Weights)

    // 3. Execute Instructions
    // Step 0
    cgra_base[0x100/4] = 0x04; // Pulse step
    cgra_base[0x100/4] = 0x00;
    while (cgra_base[0x100/4] & 0x10) { }
    // Step 1
    cgra_base[0x100/4] = 0x04; // Pulse step
    cgra_base[0x100/4] = 0x00;
    while (cgra_base[0x100/4] & 0x10) { }
    // Step 2
    cgra_base[0x100/4] = 0x04; // Pulse step
    cgra_base[0x100/4] = 0x00;
    while (cgra_base[0x100/4] & 0x10) { }

    // 4. Read Results
    uint32_t result = cgra_base[0x208/4];
    test_base[0] = result & 0xFF;
    test_base[1] = 1; // test_done

    while(1) {}
}
