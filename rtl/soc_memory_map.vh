/*
 * Copyright (c) 2026 Mounith Reddy
 * SPDX-License-Identifier: Apache-2.0
 * 
 * SoC Memory Map Definitions
 * 
 * Defines the base addresses and ranges for the system interconnect.
 */

`ifndef SOC_MEMORY_MAP_VH
`define SOC_MEMORY_MAP_VH

// Main L2 SRAM (64 KB)
`define ADDR_MEM_BASE       32'h0000_0000
`define ADDR_MEM_MASK       32'hFFFF_0000 // 64KB range

// DMA Controller
`define ADDR_DMA_BASE       32'h3000_0000
`define ADDR_DMA_MASK       32'hFFFF_FF00 // 256 bytes

// CGRA MMIO Bridge
`define ADDR_CGRA_BASE      32'h4000_0000
`define ADDR_CGRA_MASK      32'hFFFF_E000 // 8KB range

// MX Softmax Accelerator
`define ADDR_SOFTMAX_BASE   32'h5000_0000
`define ADDR_SOFTMAX_MASK   32'hFFFF_FF00 // 256 bytes

// Testbench Observability
`define ADDR_TEST_BASE      32'h8000_0000
`define ADDR_TEST_MASK      32'hFFFF_FF00 // 256 bytes

`endif // SOC_MEMORY_MAP_VH
