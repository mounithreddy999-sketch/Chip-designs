import cocotb
from cocotb.clock import Clock
import sys
import os

# Add sw/ directory to sys.path to import our assembler and driver
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'sw'))

from cgra_assembler import CGRAAssembler
from cgra_driver import CGRADriver

@cocotb.test()
async def test_cgra_driver_app(dut):
    """Test full programming and execution flow of CGRA via driver"""
    
    # Start clock
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    
    # Initialize driver
    driver = CGRADriver(dut)
    
    # Reset
    await driver.reset()
    
    # 1. Write an assembly program
    # Simple vector MAC & routing test
    # PE00 MACs North and West, and sends output to South
    # PE01 adds Global and Acc, sends to West
    # PE10 passes Acc to North
    # PE11 adds Acc and Global, sends to North
    asm_code = """
    # Simple test program
    INST 0:
        PE00: src_a=NORTH, src_b=WEST, op=MAC, dest=SOUTH
        PE01: src_a=GLOBAL, src_b=ACC, op=ADD, dest=WEST
        PE10: src_a=ACC, src_b=GLOBAL, op=Pass_A, dest=NORTH
        PE11: src_a=ACC, src_b=GLOBAL, op=ADD, dest=NORTH
    INST 1:
        PE00: src_a=ACC, src_b=NONE, op=Pass_A, dest=ALL
        PE01: src_a=ACC, src_b=NONE, op=Pass_A, dest=ALL
        PE10: src_a=ACC, src_b=NONE, op=Pass_A, dest=ALL
        PE11: src_a=ACC, src_b=NONE, op=Pass_A, dest=ALL
    """
    
    # 2. Assemble the program
    assembler = CGRAAssembler()
    program_words = assembler.assemble(asm_code)
    
    dut._log.info(f"Assembled {len([w for w in program_words if w != 0])} instructions")
    
    # 3. Use driver to program the application
    await driver.program_application(program_words)
    dut._log.info("Finished programming memory")
    
    # 4. Set inputs
    await driver.set_boundary_inputs(
        north=[5, 0],
        south=[0, 0],
        east=[0, 0],
        west=[3, 0],
        global_bus=10
    )
    
    # 5. Run Step 1 (Instruction 0)
    await driver.run_single_step()
    
    # 6. Run Step 2 (Instruction 1)
    await driver.run_single_step()
    
    # 7. Read outputs
    outs = driver.read_outputs()
    
    dut._log.info(f"Final outputs: {outs}")
    
    # Basic assertions to ensure we don't crash and outputs are integers
    assert isinstance(outs['north'][0], int)
    assert isinstance(outs['south'][0], int)
    
    dut._log.info("CGRA Driver Test Passed!")
