import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

@cocotb.test()
async def test_soc_top(dut):
    """Test full RISC-V SoC executing firmware to drive CGRA"""
    
    # Start clock
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    
    # Reset
    dut.rst.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)
    
    # Wait for the firmware to finish executing
    # It sets test_done to 1
    
    timeout_cycles = 10000
    magic_found = False
    for i in range(timeout_cycles):
        await RisingEdge(dut.clk)
        if dut.test_done.value == 1:
            magic_found = True
            break
            
    assert magic_found, "Simulation timed out waiting for test_done"
            
    cgra_s = dut.cgra_core.out_s.value
    
    # Extract lowest 8 bits (out_s_0)
    val = int(dut.test_result.value) & 0xFF
    result = val if val <= 127 else val - 256
    
    dut._log.info(f"RISC-V Firmware finished executing.")
    dut._log.info(f"Full 32-bit result: {dut.test_result.value.integer}")
    dut._log.info(f"Extracted out_s_0: {result}")
    
    # Instruction 0 MACs north*west (5*3 = 15)
    # Then instruction 1 passes Acc (15) to south output.
    # Result should be 15.
    assert result == 15, f"Expected 15, got {result}"
    
    dut._log.info("SoC Test Passed!")
