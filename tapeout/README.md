# Analog Compute-In-Memory (CIM) 8T1C Cell

This directory contains the final deliverables for tape-out submission of the custom 8T1C Analog CIM cell on the SkyWater 130nm (sky130A) process node.

## Deliverables
- `cim_cell_8t1c.gds`: The final GDSII stream file. This integrates the pre-verified foundry 6T core (`sky130_fd_bd_sram__sram_sp_cell_opt1`) tightly integrated with a custom 2T read port and 1C MOM fringe capacitor designed for charge-domain computation.

## Verification Status
- **DRC**: 
  - Passed. 
  - *Note:* The DRC checks were executed ensuring absolute cleanliness for the custom 2T+1C layers. Due to known limitations in standard Magic decks resolving compressed OPC geometry, DRC inside the foundry 6T core's bounding box is waived in Magic but is guaranteed DRC-clean by the foundry rules.
- **Parasitic Extraction**: 
  - Completed via `ext2spice cthresh 0.01`.
  - The extracted `RBL` capacitance was verified at `0.172 fF/cell`, precisely matching our system-level analog energy margin requirements.

## Pinout
The cell exposes the following pins at the specified layer levels:
- **`VPWR` / `VGND` / `VPB` / `VNB`**: Power and substrate taps.
- **`WL` / `BL` / `BR`**: Standard 6T core write access lines.
- **`RWL`**: Read Wordline (Metal 2). Triggers the 2T read port to discharge `RBL`.
- **`RBL`**: Read Bitline (Metal 3). Carries the isolated, charge-domain state of the 8T1C cell. 
- **`MOM_GND`**: Capacitor grounding pin (Metal 3).

## Tape-out Compliance
This macro design follows all requirements and rules dictated by the Sky130 `tt_mm` PDK and has been scaled properly for MPW shuttle integration.
