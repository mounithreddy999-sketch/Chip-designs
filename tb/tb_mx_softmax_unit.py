import cocotb
from cocotb.triggers import RisingEdge, Timer
from cocotb.clock import Clock
import random

# Helper models for verification
def mx_pwl_exp_ref(in_data):
    if in_data & 0x8000:
        in_val = in_data - 65536
    else:
        in_val = in_data

    if in_val >= 0:
        return 0x7FFF # 1.0 in Q1.15
    
    z = -in_val
    if z >= 0x4000: # 4.0 in Q4.12
        base_val = 0
        slope = 0
        offset = 0x4000
    elif z >= 0x3000: # 3.0 in Q4.12
        base_val = 1631
        slope = 1031
        offset = 0x3000
    elif z >= 0x2000: # 2.0 in Q4.12
        base_val = 4435
        slope = 2803
        offset = 0x2000
    elif z >= 0x1000: # 1.0 in Q4.12
        base_val = 12055
        slope = 7620
        offset = 0x1000
    else:
        base_val = 0x7FFF
        slope = 20713
        offset = 0

    dz = z - offset
    dy_ext = dz * slope
    dy = (dy_ext >> 12) & 0xFFFF
    
    if base_val > dy:
        return base_val - dy
    else:
        return 0

def mx_pwl_recip_ref(in_data):
    in_val = in_data & 0xFFFF
    
    # default S < 1.0
    base_val = 0x7FFF
    slope = 0
    offset = 0x2000
    
    if in_val >= 0x6000: # 3.0 in Q3.13
        base_val = 10922
        slope = 2730
        offset = 0x6000
    elif in_val >= 0x4000: # 2.0 in Q3.13
        base_val = 16384
        slope = 5462
        offset = 0x4000
    elif in_val >= 0x2000: # 1.0 in Q3.13
        base_val = 0x7FFF
        slope = 16384
        offset = 0x2000
        
    dS = in_val - offset if in_val > offset else 0
    dy_ext = dS * slope
    dy = (dy_ext >> 13) & 0xFFFF
    
    if base_val > dy:
        return base_val - dy
    else:
        return 0

def mx_softmax_unit_ref(in_0, in_1, in_2, in_3):
    inputs = [in_0, in_1, in_2, in_3]
    signed_inputs = []
    for val in inputs:
        if val & 0x8000:
            signed_inputs.append(val - 65536)
        else:
            signed_inputs.append(val)
            
    max_val = max(signed_inputs)
    max_val_16 = max_val & 0xFFFF
    if max_val_16 & 0x8000:
        max_val_s16 = max_val_16 - 65536
    else:
        max_val_s16 = max_val_16
        
    d = []
    for si in signed_inputs:
        diff = (si - max_val_s16) & 0xFFFF
        if diff & 0x8000:
            d.append(diff - 65536)
        else:
            d.append(diff)
            
    exps = [mx_pwl_exp_ref(di & 0xFFFF) for di in d]
    sum_exp_q1_15 = sum(exps) & 0x3FFFF
    sum_exp_q3_13 = (sum_exp_q1_15 >> 2) & 0xFFFF
    recip = mx_pwl_recip_ref(sum_exp_q3_13)
    
    out = []
    for exp in exps:
        prod = exp * recip
        next_out = (prod >> 15) & 0xFFFF
        out.append(next_out)
        
    return out

async def reset_dut(dut):
    dut.rst.value = 1
    dut.en.value = 1
    dut.start.value = 0
    dut.in_0.value = 0
    dut.in_1.value = 0
    dut.in_2.value = 0
    dut.in_3.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)

@cocotb.test()
async def test_mx_softmax_unit(dut):
    # Start clock generator (100MHz / 10ns period)
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    # Apply Reset
    await reset_dut(dut)
    
    assert dut.out_valid.value == 0, "out_valid is asserted immediately after reset"

    # Define test cases (inputs in Q4.12)
    # Q4.12 values:
    # 0 = 0x0000
    # 1.0 = 0x1000
    # -1.0 = 0xF000 (signed 16-bit: -4096)
    # -2.0 = 0xE000 (signed 16-bit: -8192)
    # -4.0 = 0xC000 (signed 16-bit: -16384)
    
    test_cases = [
        # 1. All zero inputs
        (0x0000, 0x0000, 0x0000, 0x0000, "All Zeros"),
        # 2. Equal positive inputs
        (0x1000, 0x1000, 0x1000, 0x1000, "Equal Positives"),
        # 3. Equal negative inputs
        (0xF000, 0xF000, 0xF000, 0xF000, "Equal Negatives"),
        # 4. One dominant input
        (0x0000, 0xC000, 0xC000, 0xC000, "One Dominant"),
        # 5. Mixed values
        (0x0000, 0xF000, 0xE000, 0xD000, "Mixed Negative Deltas"),
        # 6. Extreme negative range (clamps to 0)
        (0x0000, 0x8000, 0x8000, 0x8000, "Extreme Negative Clamping"),
    ]

    # Add random test cases
    random.seed(42)
    for i in range(50):
        in0 = random.randint(0, 0xFFFF)
        in1 = random.randint(0, 0xFFFF)
        in2 = random.randint(0, 0xFFFF)
        in3 = random.randint(0, 0xFFFF)
        test_cases.append((in0, in1, in2, in3, f"Random Case {i}"))

    for in_0, in_1, in_2, in_3, name in test_cases:
        dut._log.info(f"Running Test: {name}")
        dut._log.info(f"Inputs: in_0={in_0:04X}, in_1={in_1:04X}, in_2={in_2:04X}, in_3={in_3:04X}")
        
        # Calculate expected results using reference model
        expected_outs = mx_softmax_unit_ref(in_0, in_1, in_2, in_3)
        
        # Start transaction
        dut.in_0.value = in_0
        dut.in_1.value = in_1
        dut.in_2.value = in_2
        dut.in_3.value = in_3
        dut.start.value = 1
        await RisingEdge(dut.clk)
        dut.start.value = 0
        
        # Wait for out_valid
        cycles = 0
        while dut.out_valid.value == 0:
            await RisingEdge(dut.clk)
            cycles += 1
            if cycles > 10:
                raise AssertionError("Timeout waiting for out_valid")
        
        # Retrieve outputs
        out_0 = int(dut.out_0.value)
        out_1 = int(dut.out_1.value)
        out_2 = int(dut.out_2.value)
        out_3 = int(dut.out_3.value)
        
        dut._log.info(f"Outputs: out_0={out_0:04X}, out_1={out_1:04X}, out_2={out_2:04X}, out_3={out_3:04X}")
        dut._log.info(f"Expected: out_0={expected_outs[0]:04X}, out_1={expected_outs[1]:04X}, out_2={expected_outs[2]:04X}, out_3={expected_outs[3]:04X}")
        
        # Verify sum
        out_sum = out_0 + out_1 + out_2 + out_3
        dut._log.info(f"Probability Sum: {out_sum} / 32768 (approx {out_sum / 32768.0:.4f})")
        
        # Assert against expected outputs from reference model
        assert out_0 == expected_outs[0], f"Mismatch out_0: expected {expected_outs[0]}, got {out_0}"
        assert out_1 == expected_outs[1], f"Mismatch out_1: expected {expected_outs[1]}, got {out_1}"
        assert out_2 == expected_outs[2], f"Mismatch out_2: expected {expected_outs[2]}, got {out_2}"
        assert out_3 == expected_outs[3], f"Mismatch out_3: expected {expected_outs[3]}, got {out_3}"
        
        # We also want to verify the sum of probabilities is ~1.0.
        # Since it is a fixed-point PWL approximation with limited precision, the sum should be close to 1.0 (32768).
        # Let's check if the sum is within a reasonable tolerance (e.g., within 15% of 32768, which is +/- 4915).
        # PWL softmax sum is mathematically bound in [0.99, 1.13] for our segments.
        assert abs(out_sum - 32768) < 4915, f"Probability sum {out_sum} is too far from 32768"

        # Let's wait a cycle before the next test case
        await RisingEdge(dut.clk)

    dut._log.info("All mx_softmax_unit tests passed successfully!")
