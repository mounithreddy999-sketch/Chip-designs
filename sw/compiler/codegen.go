package main

import (
	"fmt"
	"os"
)

func encodeLui(rd, imm uint32) uint32 {
	return ((imm & 0xFFFFF) << 12) | (rd << 7) | 0x37
}

func encodeAddi(rd, rs1, imm uint32) uint32 {
	return ((imm & 0xFFF) << 20) | (rs1 << 15) | (0 << 12) | (rd << 7) | 0x13
}

func encodeSw(rs1, rs2, imm uint32) uint32 {
	imm11_5 := (imm >> 5) & 0x7F
	imm4_0 := imm & 0x1F
	return (imm11_5 << 25) | (rs2 << 20) | (rs1 << 15) | (2 << 12) | (imm4_0 << 7) | 0x23
}

func encodeLw(rd, rs1, imm uint32) uint32 {
	return ((imm & 0xFFF) << 20) | (rs1 << 15) | (2 << 12) | (rd << 7) | 0x03
}

func encodeAndi(rd, rs1, imm uint32) uint32 {
	return ((imm & 0xFFF) << 20) | (rs1 << 15) | (7 << 12) | (rd << 7) | 0x13
}

func encodeBne(rs1, rs2, imm uint32) uint32 {
	imm12 := (imm >> 12) & 1
	imm11 := (imm >> 11) & 1
	imm10_5 := (imm >> 5) & 0x3F
	imm4_1 := (imm >> 1) & 0xF
	return (imm12 << 31) | (imm10_5 << 25) | (rs2 << 20) | (rs1 << 15) | (1 << 12) | (imm4_1 << 8) | (imm11 << 7) | 0x63
}

func encodeJal(rd, imm uint32) uint32 {
	imm20 := (imm >> 20) & 1
	imm19_12 := (imm >> 12) & 0xFF
	imm11 := (imm >> 11) & 1
	imm10_1 := (imm >> 1) & 0x3FF
	return (imm20 << 31) | (imm10_1 << 21) | (imm11 << 20) | (imm19_12 << 12) | (rd << 7) | 0x6F
}

func loadImmediate(rd, imm uint32) []uint32 {
	upper := (imm + 0x800) >> 12
	lower := imm & 0xFFF
	return []uint32{
		encodeLui(rd, upper),
		encodeAddi(rd, rd, lower),
	}
}

func GenerateFirmware(model *Model, instructions []Instruction, outputPath string) error {
	const ZERO = 0
	const T0 = 5
	const T1 = 6
	const T2 = 7
	const T3 = 28 // New base register for 0x4000_1000

	var rv []uint32

	// Base = 0x40000000
	rv = append(rv, loadImmediate(T0, 0x40000000)...)
	// Base2 = 0x40001000
	rv = append(rv, loadImmediate(T3, 0x40001000)...)

	// 1. Program Instructions (8 chunks of 32-bits each)
	for i, inst := range instructions {
		for chunk := uint32(0); chunk < 8; chunk++ {
			pe1 := uint32(inst[chunk*2])
			pe2 := uint32(inst[chunk*2+1])
			data := pe1 | (pe2 << 16)

			rv = append(rv, loadImmediate(T1, data)...)
			// offset from T0 (0x4000_0000) is chunk*4 (max 28, fits in 12 bits)
			rv = append(rv, encodeSw(T0, T1, chunk*4))
		}
		// Commit to sequencer memory
		// offset from T3 (0x4000_1000) is 0x004
		rv = append(rv, loadImmediate(T1, uint32(i))...)
		rv = append(rv, encodeSw(T3, T1, 0x004))
	}

	// 2. Write Input Data
	// For testing, write random bytes to North and West
	// data_n @ 0x1100 -> offset 0x100 from T3
	// data_w @ 0x110C -> offset 0x10C from T3
	rv = append(rv, loadImmediate(T1, 0x05050505)...)
	rv = append(rv, encodeSw(T3, T1, 0x100))

	rv = append(rv, loadImmediate(T1, 0x03030303)...)
	rv = append(rv, encodeSw(T3, T1, 0x10C))

	// 3. Execute Loop
	for i := 0; i < len(instructions); i++ {
		// Pulse step (CSR @ 0x1000 -> offset 0x000 from T3)
		rv = append(rv, loadImmediate(T1, 4)...)
		rv = append(rv, encodeSw(T3, T1, 0x000))
		rv = append(rv, encodeSw(T3, ZERO, 0x000))

		// Poll CSR[4] for completion
		rv = append(rv, encodeLw(T1, T3, 0x000))
		rv = append(rv, encodeAndi(T1, T1, 16))
		rv = append(rv, encodeBne(T1, ZERO, 0xFFFFFFF8)) // -8
	}

	// 4. Read Result
	// out_s @ 0x1204 -> offset 0x204 from T3
	rv = append(rv, encodeLw(T2, T3, 0x204)) 
	rv = append(rv, loadImmediate(T1, 0x80000000)...)
	rv = append(rv, encodeSw(T1, T2, 0x000))

	rv = append(rv, loadImmediate(T2, 1)...)
	rv = append(rv, encodeSw(T1, T2, 0x004))

	// Inf Loop
	rv = append(rv, encodeJal(ZERO, 0))

	f, err := os.Create(outputPath)
	if err != nil {
		return err
	}
	defer f.Close()

	for _, inst := range rv {
		fmt.Fprintf(f, "%08x\n", inst)
	}

	return nil
}
