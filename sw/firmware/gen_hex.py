import struct

def encode_lui(rd, imm):
    return ((imm & 0xFFFFF) << 12) | (rd << 7) | 0x37

def encode_addi(rd, rs1, imm):
    if imm < 0: imm = (1 << 12) + imm
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (0 << 12) | (rd << 7) | 0x13

def encode_sw(rs1, rs2, imm):
    if imm < 0: imm = (1 << 12) + imm
    imm11_5 = (imm >> 5) & 0x7F
    imm4_0 = imm & 0x1F
    return (imm11_5 << 25) | (rs2 << 20) | (rs1 << 15) | (2 << 12) | (imm4_0 << 7) | 0x23

def encode_bne(rs1, rs2, imm):
    if imm < 0: imm = (1 << 13) + imm
    imm12 = (imm >> 12) & 1
    imm11 = (imm >> 11) & 1
    imm10_5 = (imm >> 5) & 0x3F
    imm4_1 = (imm >> 1) & 0xF
    return (imm12 << 31) | (imm10_5 << 25) | (rs2 << 20) | (rs1 << 15) | (1 << 12) | (imm4_1 << 8) | (imm11 << 7) | 0x63

def encode_jal(rd, imm):
    if imm < 0: imm = (1 << 21) + imm
    imm20 = (imm >> 20) & 1
    imm19_12 = (imm >> 12) & 0xFF
    imm11 = (imm >> 11) & 1
    imm10_1 = (imm >> 1) & 0x3FF
    return (imm20 << 31) | (imm10_1 << 21) | (imm11 << 20) | (imm19_12 << 12) | (rd << 7) | 0x6F

# Registers
ZERO = 0
T0 = 5
T1 = 6
T2 = 7

instructions = []

# Base = 0x40000000 (ATTENTION_BASE)
instructions.append(encode_lui(T0, 0x40000))

# ----------------------------------------------------
# PIM Weight Configuration
# ----------------------------------------------------
# PIM_K Base = 0x40000100. PIM_V Base = 0x40000200.
# We will write an identity matrix (1 on diagonal, 0 elsewhere) to both.
for row in range(4):
    for col in range(4):
        val = 1 if row == col else 0
        offset_k = 0x100 + (row * 4 + col) * 4
        offset_v = 0x200 + (row * 4 + col) * 4
        
        # Write to PIM_K
        if val != 0:
            instructions.append(encode_addi(T1, ZERO, val))
            instructions.append(encode_sw(T0, T1, offset_k))
        else:
            instructions.append(encode_sw(T0, ZERO, offset_k))
            
        # Write to PIM_V
        if val != 0:
            # We already have val in T1 if val != 0
            instructions.append(encode_sw(T0, T1, offset_v))
        else:
            instructions.append(encode_sw(T0, ZERO, offset_v))

# ----------------------------------------------------
# Write inputs to SRAM for DMA (Q Vectors)
# ----------------------------------------------------
# We need to stream 3 vectors of 32 bits (4x8 bits) to complete the 3-cycle stream.
# SRAM[0x2000] = 0x01020304 (Q vector 0)
instructions.append(encode_lui(T1, 0x00002))
instructions.append(encode_lui(T2, 0x01020))
instructions.append(encode_addi(T2, T2, 0x304))
instructions.append(encode_sw(T1, T2, 0x000)) 

# SRAM[0x2004] = 0x01020304 (Q vector 1)
instructions.append(encode_sw(T1, T2, 0x004)) 

# SRAM[0x2008] = 0x01020304 (Q vector 2)
instructions.append(encode_sw(T1, T2, 0x008)) 

# SRAM[0x200C] = 0x01020304 (Q vector 3)
instructions.append(encode_sw(T1, T2, 0x00C)) 

# Start DMA N (0x30000000)
instructions.append(encode_lui(T2, 0x30000))
instructions.append(encode_sw(T2, T1, 0x000)) # DMA_N SRC_ADDR = 0x2000
instructions.append(encode_addi(T1, ZERO, 4)) # Stream 4 words
instructions.append(encode_sw(T2, T1, 0x004)) # DMA_N LENGTH = 4
instructions.append(encode_addi(T1, ZERO, 1))
instructions.append(encode_sw(T2, T1, 0x008)) # DMA_N START = 1

# Start Pipeline via 0x40000000 (ATTENTION_BASE)
instructions.append(encode_lui(T0, 0x40000))
instructions.append(encode_addi(T1, ZERO, 1))
instructions.append(encode_sw(T0, T1, 0x000))

# Wait loops
instructions.append(encode_addi(T1, ZERO, 200))
instructions.append(encode_addi(T1, T1, -1))
instructions.append(encode_bne(T1, ZERO, -4))

# Write done to Testbench (0x80000004)
instructions.append(encode_lui(T1, 0x80000))
instructions.append(encode_addi(T2, ZERO, 1))
instructions.append(encode_sw(T1, T2, 0x004))

# Inf loop
instructions.append(encode_jal(ZERO, 0))

# Write to hex
with open('firmware.hex', 'w') as f:
    for instr in instructions:
        f.write(f"{instr:08x}\n")
    print("Generated firmware.hex successfully.")
