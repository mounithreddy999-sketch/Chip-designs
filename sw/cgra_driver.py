# Software Driver for CGRA Sequencer & Mesh Integration
# Can be used in Cocotb simulation environments to interface with the sequencer.

import cocotb
from cocotb.triggers import RisingEdge, Timer

class CGRADriver:
    def __init__(self, dut):
        """
        dut: Top-level cocotb testbench instance.
             Expected to have standard control and programming pins matching tb_cgra_sequencer.v
        """
        self.dut = dut

    async def reset(self):
        """
        Asserts active-high reset for 2 clock cycles and cleans up control signals.
        """
        self.dut.rst.value = 1
        self.dut.inst_write_en.value = 0
        self.dut.inst_write_addr.value = 0
        self.dut.inst_write_data.value = 0
        self.dut.start.value = 0
        self.dut.stop.value = 0
        self.dut.step.value = 0
        self.dut.loop_en.value = 0

        self.dut.data_n_0.value = 0
        self.dut.data_n_1.value = 0
        self.dut.data_s_0.value = 0
        self.dut.data_s_1.value = 0
        self.dut.data_e_0.value = 0
        self.dut.data_e_1.value = 0
        self.dut.data_w_0.value = 0
        self.dut.data_w_1.value = 0
        self.dut.data_global.value = 0

        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 0
        await RisingEdge(self.dut.clk)

    async def program_instruction(self, addr, microcode):
        """
        Writes a single 64-bit microcode word to the sequencer memory.
        """
        self.dut.inst_write_addr.value = addr
        self.dut.inst_write_data.value = microcode
        self.dut.inst_write_en.value = 1
        await RisingEdge(self.dut.clk)
        # Small delay to ensure hold time before deasserting
        await Timer(1, unit="ns")
        self.dut.inst_write_en.value = 0

    async def program_application(self, program):
        """
        program: List of up to 32 64-bit integers.
        """
        for addr, word in enumerate(program):
            if addr >= 32:
                break
            await self.program_instruction(addr, word)
        # Extra cycle to ensure sequencer is back to idle programming state
        await RisingEdge(self.dut.clk)

    async def set_boundary_inputs(self, north=[0,0], south=[0,0], east=[0,0], west=[0,0], global_bus=0):
        """
        Sets values on boundary data ports of the mesh.
        """
        self.dut.data_n_0.value = north[0]
        self.dut.data_n_1.value = north[1]
        self.dut.data_s_0.value = south[0]
        self.dut.data_s_1.value = south[1]
        self.dut.data_e_0.value = east[0]
        self.dut.data_e_1.value = east[1]
        self.dut.data_w_0.value = west[0]
        self.dut.data_w_1.value = west[1]
        self.dut.data_global.value = global_bus

    async def run_single_step(self):
        """
        Triggers a single-step execution and waits for execution cycle to finish.
        Sequencer state loop: IDLE -> CFG_00 -> CFG_01 -> CFG_10 -> CFG_11 -> EXEC -> NEXT -> IDLE (7 cycles)
        """
        self.dut.step.value = 1
        await RisingEdge(self.dut.clk)
        await Timer(1, unit="ns")
        self.dut.step.value = 0

        # Wait until sequencer goes through configuration and exec back to idle
        # We can poll self.dut.sequencer.state if it's visible, or just wait 7 cycles
        for _ in range(7):
            await RisingEdge(self.dut.clk)
        await Timer(1, unit="ns")

    async def run_continuous(self, loop=False, run_cycles=10):
        """
        Triggers continuous execution of the sequencer.
        """
        self.dut.loop_en.value = 1 if loop else 0
        self.dut.start.value = 1
        await RisingEdge(self.dut.clk)
        await Timer(1, unit="ns")
        self.dut.start.value = 0

        # Let it run for the specified clock cycles
        for _ in range(run_cycles):
            await RisingEdge(self.dut.clk)

    async def stop_execution(self):
        """
        Stops running execution.
        """
        self.dut.stop.value = 1
        await RisingEdge(self.dut.clk)
        await Timer(1, unit="ns")
        self.dut.stop.value = 0
        await RisingEdge(self.dut.clk)

    def read_outputs(self):
        """
        Returns the current boundary outputs of the mesh.
        """
        return {
            'north': [int(self.dut.out_n_0.value.to_signed()), int(self.dut.out_n_1.value.to_signed())],
            'south': [int(self.dut.out_s_0.value.to_signed()), int(self.dut.out_s_1.value.to_signed())],
            'east':  [int(self.dut.out_e_0.value.to_signed()), int(self.dut.out_e_1.value.to_signed())],
            'west':  [int(self.dut.out_w_0.value.to_signed()), int(self.dut.out_w_1.value.to_signed())]
        }
