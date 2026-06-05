#include <stdint.h>

// ----------------------------------------------------
// SoC Memory Map Definitions
// ----------------------------------------------------
#define SRAM_BASE       0x00000000
#define DMA_N_BASE      0x30000000
#define DMA_W_BASE      0x30001000
#define ATTENTION_BASE  0x40000000
#define TEST_BASE       0x80000000

// Peripheral Pointers
volatile uint32_t* dma_n    = (volatile uint32_t*) DMA_N_BASE;
volatile uint32_t* dma_w    = (volatile uint32_t*) DMA_W_BASE;
volatile uint32_t* att      = (volatile uint32_t*) ATTENTION_BASE;
volatile uint32_t* test     = (volatile uint32_t*) TEST_BASE;

// Data Buffers in L2 SRAM
// We use Q4.12 signed format for MAC, wait, input flat was just raw ints for testing
volatile uint32_t act_input_buffer[1] = { 5 }; // North (Activations)
volatile uint32_t wgt_input_buffer[1] = { 3 }; // West (Weights)

void dma_transfer(volatile uint32_t* dma, uint32_t src, uint32_t len) {
    dma[0] = src; // Source Addr
    dma[1] = len; // Length (words)
    dma[2] = 1;   // Start DMA (bit 0)
    // Wait for DMA done (bit 2)
    // actually, axi_stream_dma clears busy when done
    // let's just let it stream, the CGRA will consume it
}

void main() {
    // 1. Program CGRA Instructions into Attention Sequencer (Offset 0x100)
    // Note: The attention_block expects 32-bit words at 0x100 offset
    // Instruction 0: MAC North*West
    // 0x00000218 -> src_n=1, src_w=2, src_s=0, dst=1 (Acc), op=MAC
    att[0x100/4] = 0x00000218; // PE00 (Address 0)
    
    // 2. Stream Data via AXI-Stream DMAs
    dma_transfer(dma_n, (uint32_t)&act_input_buffer[0], 1);
    dma_transfer(dma_w, (uint32_t)&wgt_input_buffer[0], 1);

    // 3. Execute Attention Sequencer (pulse step)
    att[0x0] = 0x04; // Step bit
    att[0x0] = 0x00;

    // Wait a few cycles for CGRA and Softmax pipeline to complete
    for (volatile int i = 0; i < 20; i++) {}

    // The attention_block streams the Softmax output directly to the Testbench Result MMIO
    // we can just read test[0] to verify or signal done
    test[1] = 1;  // Write to test_done

    while(1) {}
}
