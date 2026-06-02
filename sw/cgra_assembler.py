#!/usr/bin/env python3
import sys
import os
import re

# Mapping tables
SRC_MAP = {
    'north': 0, 'n': 0,
    'south': 1, 's': 1,
    'east': 2, 'e': 2,
    'west': 3, 'w': 3,
    'global': 4, 'g': 4, 'global_bus': 4,
    'acc': 5, 'a': 5, 'accumulator': 5,
    'none': 7
}

OP_MAP = {
    'mac': 0,
    'add': 1,
    'pass_a': 2, 'passa': 2,
    'pass_b': 3, 'passb': 3
}

DEST_MAP = {
    'all': 0,
    'north': 1, 'n': 1,
    'south': 2, 's': 2,
    'east': 3, 'e': 3,
    'west': 4, 'w': 4,
    'none': 7
}

class CGRAAssembler:
    def __init__(self):
        # 32 instructions, each is a list of 4 PE config words (PE00, PE01, PE10, PE11)
        self.program = [[0, 0, 0, 0] for _ in range(32)]

    def parse_pe_config(self, config_str, line_num):
        # Parses "src_a=N, src_b=W, op=ADD, dest=W"
        parts = re.split(r'[,\s]+', config_str.strip())
        src_a = 0
        src_b = 0
        op = 0
        dest = 0

        for part in parts:
            if not part:
                continue
            if '=' not in part:
                raise ValueError(f"Line {line_num}: Invalid assignment '{part}'")
            key, val = part.split('=', 1)
            key = key.strip().lower()
            val = val.strip().lower()

            if key in ['src_a', 'a']:
                if val not in SRC_MAP:
                    raise ValueError(f"Line {line_num}: Unknown source '{val}'")
                src_a = SRC_MAP[val]
            elif key in ['src_b', 'b']:
                if val not in SRC_MAP:
                    raise ValueError(f"Line {line_num}: Unknown source '{val}'")
                src_b = SRC_MAP[val]
            elif key in ['op']:
                if val not in OP_MAP:
                    raise ValueError(f"Line {line_num}: Unknown operation '{val}'")
                op = OP_MAP[val]
            elif key in ['dest', 'dest_route', 'out']:
                if val not in DEST_MAP:
                    raise ValueError(f"Line {line_num}: Unknown destination '{val}'")
                dest = DEST_MAP[val]
            else:
                raise ValueError(f"Line {line_num}: Unknown key '{key}'")

        # Encode 16-bit configuration word
        # [2:0]   src_a
        # [5:3]   src_b
        # [7:6]   op
        # [10:8]  dest
        # [15:11] unused (0)
        word = (src_a & 0x7) | ((src_b & 0x7) << 3) | ((op & 0x3) << 6) | ((dest & 0x7) << 8)
        return word

    def assemble(self, asm_text):
        active_addr = 0
        lines = asm_text.splitlines()

        for idx, line in enumerate(lines):
            line_num = idx + 1
            # Remove comments
            line = re.sub(r'(#|//).*$', '', line).strip()
            if not line:
                continue

            # Check for INST header: "INST 3:"
            inst_match = re.match(r'^inst\s+(\d+)\s*:$', line, re.IGNORECASE)
            if inst_match:
                addr = int(inst_match.group(1))
                if addr < 0 or addr > 31:
                    raise ValueError(f"Line {line_num}: Instruction address {addr} out of bounds (0-31)")
                active_addr = addr
                continue

            # Check for PE assignment: "PE00: src_a=..."
            pe_match = re.match(r'^pe(00|01|10|11)\s*:\s*(.*)$', line, re.IGNORECASE)
            if pe_match:
                pe_name = pe_match.group(1)
                config_str = pe_match.group(2)
                
                # Determine index: PE00 -> 0, PE01 -> 1, PE10 -> 2, PE11 -> 3
                pe_idx_map = {'00': 0, '01': 1, '10': 2, '11': 3}
                pe_idx = pe_idx_map[pe_name]

                word = self.parse_pe_config(config_str, line_num)
                self.program[active_addr][pe_idx] = word
                continue

            raise ValueError(f"Line {line_num}: Unrecognized syntax: '{line}'")

        # Package each instruction into a 64-bit word
        # [15:0]  PE00
        # [31:16] PE01
        # [47:32] PE10
        # [63:48] PE11
        packed_program = []
        for inst in self.program:
            word64 = inst[0] | (inst[1] << 16) | (inst[2] << 32) | (inst[3] << 48)
            packed_program.append(word64)

        return packed_program

def main():
    if len(sys.argv) > 1 and sys.argv[1] == '--test':
        # Self tests
        assembler = CGRAAssembler()
        asm = """
        # Test program
        INST 0:
            PE00: src_a=NORTH, src_b=WEST, op=ADD, dest=WEST
            PE01: src_a=GLOBAL, src_b=ACC, op=MAC, dest=NONE
        INST 1:
            PE10: src_a=ACC, src_b=GLOBAL, op=pass_a, dest=NORTH
        """
        try:
            prog = assembler.assemble(asm)
            assert len(prog) == 32
            # PE00 of INST 0: src_a=0 (North), src_b=3 (West), op=1 (ADD), dest=4 (West)
            # Word: 0 | (3 << 3) | (1 << 6) | (4 << 8) = 24 + 64 + 1024 = 1112 (hex 0458)
            assert prog[0] & 0xFFFF == 0x0458
            # PE01 of INST 0: src_a=4 (Global), src_b=5 (Acc), op=0 (MAC), dest=7 (None)
            # Word: 4 | (5 << 3) | (0 << 6) | (7 << 8) = 4 + 40 + 0 + 1792 = 1836 (hex 072C)
            assert (prog[0] >> 16) & 0xFFFF == 0x072C
            print("[PASS] CGRA Assembler self-test completed successfully!")
            sys.exit(0)
        except Exception as e:
            print(f"[FAIL] CGRA Assembler self-test failed: {e}")
            sys.exit(1)

    if len(sys.argv) < 2:
        print("Usage: python cgra_assembler.py <input.asm> [-o <output.hex>]")
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = None
    if '-o' in sys.argv:
        idx = sys.argv.index('-o')
        if idx + 1 < len(sys.argv):
            output_file = sys.argv[idx + 1]

    if not os.path.exists(input_file):
        print(f"Error: Input file '{input_file}' not found.")
        sys.exit(1)

    with open(input_file, 'r') as f:
        asm_text = f.read()

    assembler = CGRAAssembler()
    try:
        prog = assembler.assemble(asm_text)
        if output_file:
            with open(output_file, 'w') as f:
                for word in prog:
                    f.write(f"{word:016X}\n")
            print(f"Assembly successful. Output written to {output_file}")
        else:
            for idx, word in enumerate(prog):
                if word != 0:
                    print(f"INST {idx:02d}: {word:016X}")
    except Exception as e:
        print(f"Assembly Error: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()
