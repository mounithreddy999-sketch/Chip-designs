package main

import (
	"fmt"
)

// A single 256-bit microcode instruction (16 PEs x 16-bits)
type Instruction [16]uint16

// CGRA Operations
const (
	OP_MAC    = 0
	OP_ADD    = 1
	OP_PASS_A = 2
	OP_PASS_B = 3
)

// Source Routing Directions (src_a and src_b)
const (
	SRC_NORTH  = 0
	SRC_SOUTH  = 1
	SRC_EAST   = 2
	SRC_WEST   = 3
	SRC_GLOBAL = 4
	SRC_ACC    = 5
)

// Destination Routing Directions (dest_route)
const (
	DEST_ALL   = 0
	DEST_NORTH = 1
	DEST_SOUTH = 2
	DEST_EAST  = 3
	DEST_WEST  = 4
)

// Maps model to a list of microcode instructions
func MapToCGRA(model *Model) ([]Instruction, error) {
	var instructions []Instruction

	for _, layer := range model.Layers {
		if layer.Type == "Linear" {
			var inst Instruction
			
			// For a 4x4 mesh, we use PE(0,0) for the MAC.
			// And we route the output down to PE(3,0) using PASS_A.
			// PE indices: (r, c) -> r*4 + c
			// PE(0,0) = 0, PE(1,0) = 4, PE(2,0) = 8, PE(3,0) = 12

			// MAC Instruction
			inst[0] = uint16(SRC_NORTH) | (uint16(SRC_WEST) << 3) | (OP_MAC << 6) | (DEST_SOUTH << 8)
			inst[4] = uint16(SRC_NORTH) | (OP_PASS_A << 6) | (DEST_SOUTH << 8)
			inst[8] = uint16(SRC_NORTH) | (OP_PASS_A << 6) | (DEST_SOUTH << 8)
			inst[12] = uint16(SRC_NORTH) | (OP_PASS_A << 6) | (DEST_SOUTH << 8)

			// Flush Instruction (PASS_A to flush acc south)
			var flush Instruction
			flush[0] = uint16(SRC_ACC) | (OP_PASS_A << 6) | (DEST_SOUTH << 8)
			flush[4] = uint16(SRC_NORTH) | (OP_PASS_A << 6) | (DEST_SOUTH << 8)
			flush[8] = uint16(SRC_NORTH) | (OP_PASS_A << 6) | (DEST_SOUTH << 8)
			flush[12] = uint16(SRC_NORTH) | (OP_PASS_A << 6) | (DEST_SOUTH << 8)

			// We need `in_dim` MAC operations
			for i := 0; i < layer.InputDim; i++ {
				instructions = append(instructions, inst)
			}
			// 4 cycles to flush the 4x4 systolic pipeline completely
			instructions = append(instructions, flush)
			instructions = append(instructions, flush)
			instructions = append(instructions, flush)
			instructions = append(instructions, flush)
			
		} else {
			return nil, fmt.Errorf("unsupported layer type: %s", layer.Type)
		}
	}

	return instructions, nil
}
