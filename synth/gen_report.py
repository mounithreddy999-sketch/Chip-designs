#!/usr/bin/env python3
"""
Comparative Synthesis Report Generator
Parses Yosys stat output files for both N=4 and N=8 configurations,
and generates a consolidated Markdown report showing area scaling.
"""

import re
import os
import sys
from datetime import datetime

def parse_stat_file(filepath):
    """Parse a Yosys stat output file and extract per-module statistics.
    Returns (modules_dict, aggregate_dict_or_None).
    """
    modules = {}
    aggregate = None
    current_target = None

    if not os.path.exists(filepath):
        return modules, aggregate

    with open(filepath, 'r') as f:
        for line in f:
            line = line.rstrip()

            # Match module header: === module_name ===
            mod_match = re.match(r'^=== (.+?) ===$', line)
            if mod_match:
                name = mod_match.group(1).strip()
                entry = {
                    'wires': 0, 'wire_bits': 0,
                    'cells': 0, 'cell_types': {},
                    'memories': 0, 'memory_bits': 0,
                }
                if name == 'design hierarchy':
                    aggregate = entry
                    current_target = aggregate
                else:
                    modules[name] = entry
                    current_target = entry
                continue

            if current_target is None:
                continue

            # Match statistics lines
            num_match = re.match(r'^\s+Number of (\w[\w\s]*?):\s+(\d+)', line)
            if num_match:
                key = num_match.group(1).strip()
                val = int(num_match.group(2))
                if key == 'wires':
                    current_target['wires'] = val
                elif key == 'wire bits':
                    current_target['wire_bits'] = val
                elif key == 'cells':
                    current_target['cells'] = val
                elif key == 'memories':
                    current_target['memories'] = val
                elif key == 'memory bits':
                    current_target['memory_bits'] = val
                continue

            # Match cell type lines: $_ANDNOT_  1234
            cell_match = re.match(r'^\s+(\S+)\s+(\d+)', line)
            if cell_match:
                cell_name = cell_match.group(1)
                cell_count = int(cell_match.group(2))
                if cell_name.startswith('$_') or cell_name.startswith('SB_'):
                    current_target['cell_types'][cell_name] = cell_count
                # Generic gate-level latch/flip-flop models
                elif any(pat in cell_name for pat in ['dff', 'DFF', 'sdff', 'SDFF']):
                    current_target['cell_types'][cell_name] = cell_count

    return modules, aggregate

def parse_sky130_report(filepath):
    """Parse Yosys stat report for Sky130 standard cell synthesis.
    Returns a dict with cells, ffs, comb, area, and cell_types distribution.
    """
    stats = {
        'cells': 0,
        'ffs': 0,
        'comb': 0,
        'area': 0.0,
        'cell_types': {}
    }
    if not os.path.exists(filepath):
        return None
        
    in_hierarchy = False
    with open(filepath, 'r') as f:
        for line in f:
            line = line.rstrip()
            
            # Start parsing only when we reach the design hierarchy section
            if line.startswith('=== design hierarchy ==='):
                in_hierarchy = True
                continue
                
            if not in_hierarchy:
                continue
                
            # Match number of cells
            num_match = re.match(r'^\s+Number of cells:\s+(\d+)', line)
            if num_match:
                stats['cells'] = int(num_match.group(1))
                continue
                
            # Match cell name and count
            cell_match = re.match(r'^\s+(\S+)\s+(\d+)', line)
            if cell_match:
                cell_name = cell_match.group(1)
                cell_count = int(cell_match.group(2))
                # Skip wire/bit counts or non-cell names
                if cell_name.startswith('sky130_fd_sc_hd__'):
                    stats['cell_types'][cell_name] = cell_count
                    # Check if it is a flip-flop
                    if '__df' in cell_name:
                        stats['ffs'] += cell_count
                continue
                
            # Match Chip area line
            area_match = re.search(r'Chip area for.*:\s*([0-9.]+)', line)
            if area_match:
                stats['area'] = float(area_match.group(1))
                
    stats['comb'] = stats['cells'] - stats['ffs']
    return stats

def count_ffs(cell_types):
    ff_count = 0
    for name, count in cell_types.items():
        if any(pat in name for pat in ['DFF', 'SDFF', 'DFFE', 'SB_DFF', 'dff']):
            ff_count += count
    return ff_count

def count_luts(cell_types):
    lut_count = 0
    for name, count in cell_types.items():
        if 'SB_LUT4' in name:
            lut_count += count
    return lut_count

def count_brams(cell_types):
    bram_count = 0
    for name, count in cell_types.items():
        if 'SB_RAM' in name:
            bram_count += count
    return bram_count

def count_carries(cell_types):
    carry_count = 0
    for name, count in cell_types.items():
        if 'SB_CARRY' in name:
            carry_count += count
    return carry_count

def generate_report(g4_mods, g4_agg, g8_mods, g8_agg, i4_mods, sky130_stats, output_path):
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    lines = []
    
    lines.append('# Synthesis Scaling Report: Microscaled Attention Core')
    lines.append('')
    lines.append(f'**Generated**: {timestamp}')
    lines.append(f'**Tool**: Yosys 0.33 (Open Synthesis Suite)')
    lines.append(f'**Top Module**: `mx_attention_core`')
    lines.append('')
    lines.append('This report evaluates the scaling characteristics of the design as it scales from the standard **4x4** array configuration to the scaled **8x8** array configuration.')
    lines.append('')
    
    # Section 1: Comparative Design Hierarchy
    lines.append('---')
    lines.append('## 1. Design Hierarchy Comparison')
    lines.append('')
    lines.append('| Component | 4x4 Array Design | 8x8 Scaled Design | Scaling Law |')
    lines.append('| :--- | :---: | :---: | :--- |')
    lines.append('| Systolic Mesh Size | 4x4 | 8x8 | - |')
    lines.append('| Processing Elements (PEs) | 16 | 64 | Quadratic ($N^2$) |')
    lines.append('| SRAM Buffer Word Width | 16 bits | 32 bits | Linear ($N$) |')
    lines.append('| Row-Wise Softmax Units | 4 | 8 | Linear ($N$) |')
    lines.append('| Exponentiation Units (`mx_pwl_exp`) | 16 | 64 | Quadratic ($N^2$) |')
    lines.append('| Reciprocal Units (`mx_pwl_recip`) | 4 | 8 | Linear ($N$) |')
    lines.append('')
    
    # Section 2: Generic Gate-Level Synthesis Comparison
    lines.append('---')
    lines.append('## 2. Generic Gate-Level Area Scaling')
    lines.append('')
    lines.append('### Flat Design Totals')
    lines.append('')
    
    agg4 = g4_agg if g4_agg else g4_mods.get('mx_attention_core')
    agg8 = g8_agg if g8_agg else g8_mods.get('mx_attention_core')
    
    if agg4 and agg8:
        c4, c8 = agg4['cells'], agg8['cells']
        f4, f8 = count_ffs(agg4['cell_types']), count_ffs(agg8['cell_types'])
        comb4, comb8 = c4 - f4, c8 - f8
        w4, w8 = agg4['wires'], agg8['wires']
        wb4, wb8 = agg4['wire_bits'], agg8['wire_bits']
        
        lines.append('| Metric | 4x4 Array | 8x8 Array | Scaling Ratio |')
        lines.append('| :--- | :---: | :---: | :---: |')
        lines.append(f'| **Total Cells** | {c4:,} | {c8:,} | {c8/c4:.2f}x |')
        lines.append(f'| **Flip-Flops (FFs)** | {f4:,} | {f8:,} | {f8/f4:.2f}x |')
        lines.append(f'| **Combinational Cells** | {comb4:,} | {comb8:,} | {comb8/comb4:.2f}x |')
        lines.append(f'| **Wires** | {w4:,} | {w8:,} | {w8/w4:.2f}x |')
        lines.append(f'| **Wire Bits** | {wb4:,} | {wb8:,} | {wb8/wb4:.2f}x |')
        lines.append('')
    
    lines.append('### Per-Module Statistics Comparison')
    lines.append('')
    lines.append('| Module | 4x4 Cells (FFs) | 8x8 Cells (FFs) | Growth Factor |')
    lines.append('| :--- | :---: | :---: | :---: |')
    
    module_order = ['mx_pe', 'mx_systolic_mesh', 'scratchpad_sram',
                    'mx_pwl_exp', 'mx_pwl_recip', 'mx_softmax_unit',
                    'mx_attention_core']
                    
    for mod in module_order:
        m4 = g4_mods.get(mod)
        m8 = g8_mods.get(mod)
        if m4 and m8:
            ff4 = count_ffs(m4['cell_types'])
            ff8 = count_ffs(m8['cell_types'])
            lines.append(f'| `{mod}` | {m4["cells"]:,} ({ff4:,}) | {m8["cells"]:,} ({ff8:,}) | {m8["cells"]/m4["cells"]:.2f}x |')
            
    lines.append('')

    # Section 3: iCE40 FPGA Mapping (N=4 only)
    lines.append('---')
    lines.append('## 3. iCE40 FPGA Resource Mapping (N=4)')
    lines.append('')
    lines.append('> [!NOTE]')
    lines.append('> The 8x8 scaled attention core (~300,000 gates) far exceeds the capacity of the Lattice iCE40 HX8K FPGA (which has only 7.6K logic cells). To prevent out-of-memory errors during logic optimization (ABC), physical technology mapping was performed for the N=4 design only.')
    lines.append('')
    
    i4 = i4_mods.get('mx_attention_core')
    if i4:
        lut4 = count_luts(i4['cell_types'])
        ff4 = count_ffs(i4['cell_types'])
        bram4 = count_brams(i4['cell_types'])
        carry4 = count_carries(i4['cell_types'])
        
        lc4 = max(lut4, ff4)
        hx_lcs = 7680
        hx_brams = 32
        
        lines.append('| Resource | 4x4 Used | Available | 4x4 Util % |')
        lines.append('| :------- | -------: | --------: | ---------: |')
        lines.append(f'| **Logic Cells (LCs)** | {lc4:,} | {hx_lcs:,} | {lc4/hx_lcs*100:.1f}% |')
        lines.append(f'| **LUT4s** | {lut4:,} | {hx_lcs:,} | {lut4/hx_lcs*100:.1f}% |')
        lines.append(f'| **DFFs** | {ff4:,} | {hx_lcs:,} | {ff4/hx_lcs*100:.1f}% |')
        lines.append(f'| **Carry Cells** | {carry4:,} | — | — |')
        lines.append(f'| **Block RAMs** | {bram4:,} | {hx_brams:,} | {bram4/hx_brams*100:.1f}% |')
        lines.append('')
        
        lines.append('### Fit Assessment')
        lines.append('')
        lines.append('**4x4 Attention Core**:')
        if lc4 <= hx_lcs and bram4 <= hx_brams:
            lines.append(f'> ✅ Fits on iCE40 HX8K ({lc4/hx_lcs*100:.1f}% LC, {bram4/hx_brams*100:.1f}% BRAM).')
        else:
            lines.append(f'> ⚠️ Exceeds iCE40 HX8K capacity ({lc4/hx_lcs*100:.1f}% LC, {bram4/hx_brams*100:.1f}% BRAM).')
        lines.append('')
        
    # Section 4: Sky130 ASIC Standard Cell Synthesis
    if sky130_stats:
        lines.append('---')
        lines.append('## 4. SkyWater 130nm ASIC Standard Cell Synthesis (N=4)')
        lines.append('')
        lines.append('> [!TIP]')
        lines.append('> This section presents physical technology mapping directly to SkyWater 130nm standard cells (`sky130_fd_sc_hd`) using the typical-corner liberty cell library. Gate count and area calculations are derived directly from actual standard cell geometry specs.')
        lines.append('')
        lines.append('| Metric | Value | Details |')
        lines.append('| :--- | :---: | :--- |')
        lines.append(f'| **Total cells** | {sky130_stats["cells"]:,} | Total mapped standard cells |')
        lines.append(f'| **Flip-Flops (DFX)** | {sky130_stats["ffs"]:,} | Sequential storage cells |')
        lines.append(f'| **Combinational cells** | {sky130_stats["comb"]:,} | Combinational logic gates |')
        lines.append(f'| **Estimated Cell Area** | {sky130_stats["area"]:.2f} $\\mu m^2$ | Standard cell silicon area |')
        lines.append('')
        
        # Breakdown of top 10 cell types
        lines.append('### Standard Cell Type Distribution (Top 10)')
        lines.append('')
        lines.append('| Cell Name | Count | Utilization % |')
        lines.append('| :--- | :---: | :---: |')
        sorted_cells = sorted(sky130_stats['cell_types'].items(), key=lambda x: x[1], reverse=True)
        for cell, count in sorted_cells[:10]:
            pct = (count / sky130_stats['cells']) * 100
            lines.append(f'| `{cell}` | {count:,} | {pct:.1f}% |')
        lines.append('')

    lines.append('---')
    lines.append('')
    lines.append('*Report generated by `synth/gen_report.py`*')
    
    with open(output_path, 'w') as f:
        f.write('\n'.join(lines))
        
    print(f'[SUCCESS] Comparative synthesis report written to: {output_path}')

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    out_dir = os.path.join(script_dir, 'out')
    
    gen4_path = os.path.join(out_dir, 'report_generic_4.txt')
    gen8_path = os.path.join(out_dir, 'report_generic_8.txt')
    ice4_path = os.path.join(out_dir, 'report_ice40_4.txt')
    sky130_path = os.path.join(out_dir, 'report_sky130.txt')
    report_path = os.path.join(out_dir, 'synthesis_report.md')
    
    # Parse generic reports
    g4_mods, g4_agg = parse_stat_file(gen4_path)
    g8_mods, g8_agg = parse_stat_file(gen8_path)
    
    # Parse iCE40 reports
    i4_mods, _ = parse_stat_file(ice4_path)
    
    # Parse Sky130 report
    sky130_stats = parse_sky130_report(sky130_path)
    
    print(f"Loaded N=4 generic: {len(g4_mods)} modules.")
    print(f"Loaded N=8 generic: {len(g8_mods)} modules.")
    print(f"Loaded N=4 iCE40: {len(i4_mods)} modules.")
    if sky130_stats:
        print(f"Loaded Sky130 statistics: {sky130_stats['cells']} cells.")
    else:
        print("Sky130 statistics file not found or empty.")
    
    generate_report(g4_mods, g4_agg, g8_mods, g8_agg, i4_mods, sky130_stats, report_path)

if __name__ == '__main__':
    main()
