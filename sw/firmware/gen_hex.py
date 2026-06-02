import struct

def encode_lui(rd, imm):
    return ((imm & 0xFFFFF) << 12) | (rd << 7) | 0x37

def encode_addi(rd, rs1, imm):
    # Handle negative immediates
    if imm < 0: imm = (1 << 12) + imm
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (0 << 12) | (rd << 7) | 0x13

def encode_sw(rs1, rs2, imm):
    if imm < 0: imm = (1 << 12) + imm
    imm11_5 = (imm >> 5) & 0x7F
    imm4_0 = imm & 0x1F
    return (imm11_5 << 25) | (rs2 << 20) | (rs1 << 15) | (2 << 12) | (imm4_0 << 7) | 0x23

def encode_lw(rd, rs1, imm):
    if imm < 0: imm = (1 << 12) + imm
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (2 << 12) | (rd << 7) | 0x03

def encode_andi(rd, rs1, imm):
    if imm < 0: imm = (1 << 12) + imm
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (7 << 12) | (rd << 7) | 0x13

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

# Base = 0x40000000
instructions.append(encode_lui(T0, 0x40000))

# Instruction 0
# PE00: MAC NORTH*WEST -> SOUTH. 0x0218
# PE01: NOP. 0x0000
instructions.append(encode_lui(T1, 0x00000))
instructions.append(encode_addi(T1, T1, 0x218))
instructions.append(encode_sw(T0, T1, 0x000))

# PE10: PASS_A NORTH -> SOUTH. 0x0280
# PE11: NOP. 0x0000
instructions.append(encode_lui(T1, 0x00000))
instructions.append(encode_addi(T1, T1, 0x280))
instructions.append(encode_sw(T0, T1, 0x004))

# Instruction 1
# PE00: PASS_A ACC -> SOUTH. 0x0285
# PE01: NOP. 0x0000
instructions.append(encode_lui(T1, 0x00000))
instructions.append(encode_addi(T1, T1, 0x285))
instructions.append(encode_sw(T0, T1, 0x008))

# PE10: PASS_A NORTH -> SOUTH. 0x0280
# PE11: NOP. 0x0000
instructions.append(encode_lui(T1, 0x00000))
instructions.append(encode_addi(T1, T1, 0x280))
instructions.append(encode_sw(T0, T1, 0x00C))

# 0x40000104 (data_n) = 5
instructions.append(encode_addi(T1, ZERO, 5))
instructions.append(encode_sw(T0, T1, 0x104))

# 0x40000110 (data_w) = 3
instructions.append(encode_addi(T1, ZERO, 3))
instructions.append(encode_sw(T0, T1, 0x110))

# 0x40000114 (data_g) = 10
instructions.append(encode_addi(T1, ZERO, 10))
instructions.append(encode_sw(T0, T1, 0x114))

# Pulse start (csr 0x100) = 4
instructions.append(encode_addi(T1, ZERO, 4))
instructions.append(encode_sw(T0, T1, 0x100))
# Clear start
instructions.append(encode_sw(T0, ZERO, 0x100))

# Poll loop 1
# offset 0x100: lw T1, 0x100(T0)
# andi T1, T1, 16
# bne T1, ZERO, -8
poll_loop_1_idx = len(instructions)
instructions.append(encode_lw(T1, T0, 0x100))
instructions.append(encode_andi(T1, T1, 16))
instructions.append(encode_bne(T1, ZERO, -8))

# Pulse step again (csr 0x100) = 4
instructions.append(encode_addi(T1, ZERO, 4))
instructions.append(encode_sw(T0, T1, 0x100))
instructions.append(encode_sw(T0, ZERO, 0x100))

# Poll loop 2
poll_loop_2_idx = len(instructions)
instructions.append(encode_lw(T1, T0, 0x100))
instructions.append(encode_andi(T1, T1, 16))
instructions.append(encode_bne(T1, ZERO, -8))

# Read output out_s (0x208)
instructions.append(encode_lw(T2, T0, 0x208))

# Store result to 0x80000000
instructions.append(encode_lui(T1, 0x80000))
instructions.append(encode_sw(T1, T2, 0x000))

# Write 1 to 0x80000004 to indicate done
instructions.append(encode_addi(T2, ZERO, 1))
instructions.append(encode_sw(T1, T2, 0x004))

# Infinite loop
inf_loop_idx = len(instructions)
instructions.append(encode_jal(ZERO, 0))

# Write to hex
with open('firmware.hex', 'w') as f:
    for instr in instructions:
        f.write(f"{instr:08x}\n")
    print("Generated firmware.hex successfully.")
