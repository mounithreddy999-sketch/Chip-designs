import cocotb
import random
import math
from cocotb.triggers import RisingEdge, Timer
from cocotb.clock import Clock

# Helper function to convert 4-bit unsigned value to signed integer
def to_signed_4bit(val):
    val = val & 0xF
    if val >= 8:
        return val - 16
    return val

# Helper function to pack N elements into an 8-bit aligned word
def pack_word(elements, N):
    packed = 0
    for i in range(N):
        val = int(elements[i]) & 0xFF
        packed |= (val << (8 * i))
    return packed

# Floating-point decoders to support reference modeling
def decode_e2m1(val):
    s = (val >> 3) & 1
    e = (val >> 1) & 3
    m = val & 1
    if e == 0:
        return (-1)**s * 0.5 * m # Subnormal
    else:
        return (-1)**s * 2**(e - 1) * (1.0 + m * 0.5) # Normal

def decode_e4m3(val):
    s = (val >> 7) & 1
    e = (val >> 3) & 15
    m = val & 7
    if e == 0:
        return (-1)**s * 2**(-6) * (m / 8.0) # Subnormal
    else:
        return (-1)**s * 2**(e - 7) * (1.0 + m / 8.0) # Normal

def decode_e5m2(val):
    s = (val >> 7) & 1
    e = (val >> 2) & 31
    m = val & 3
    if e == 0:
        return (-1)**s * 2**(-14) * (m / 4.0) # Subnormal
    else:
        return (-1)**s * 2**(e - 15) * (1.0 + m / 4.0) # Normal

def to_float(val, format_mode):
    if format_mode == 1:
        return decode_e2m1(val)
    elif format_mode == 2:
        return decode_e4m3(val)
    elif format_mode == 3:
        return decode_e5m2(val)
    else:
        # MXINT4 (signed 4-bit)
        v = val & 0xF
        return v - 16 if v >= 8 else v

# Piecewise-Linear (PWL) Models for Exponentiation and Reciprocal
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
    
    if in_val >= 0xE000: # 7.0 in Q3.13
        base_val = 4681
        slope = 585
        offset = 0xE000
    elif in_val >= 0xC000: # 6.0 in Q3.13
        base_val = 5461
        slope = 780
        offset = 0xC000
    elif in_val >= 0xA000: # 5.0 in Q3.13
        base_val = 6554
        slope = 1092
        offset = 0xA000
    elif in_val >= 0x8000: # 4.0 in Q3.13
        base_val = 8192
        slope = 1638
        offset = 0x8000
    elif in_val >= 0x6000: # 3.0 in Q3.13
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

def mx_softmax_unit_ref(*inputs):
    if len(inputs) == 1 and isinstance(inputs[0], (list, tuple)):
        inputs = inputs[0]
    signed_inputs = []
    for val in inputs:
        val_16 = val & 0xFFFF
        if val_16 & 0x8000:
            signed_inputs.append(val_16 - 65536)
        else:
            signed_inputs.append(val_16)
            
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
    sum_exp_q1_15 = sum(exps)
    
    sum_exp_shifted = sum_exp_q1_15 >> 2
    if sum_exp_shifted > 0xFFFF:
        sum_exp_q3_13 = 0xFFFF
    else:
        sum_exp_q3_13 = sum_exp_shifted & 0xFFFF
        
    recip = mx_pwl_recip_ref(sum_exp_q3_13)
    
    out = []
    for exp in exps:
        prod = exp * recip
        next_out = (prod >> 15) & 0xFFFF
        out.append(next_out)
        
    return out

# Matrix math helper functions
def matmul(A, B):
    M, K, N = len(A), len(A[0]), len(B[0])
    res = [[0]*N for _ in range(M)]
    for r in range(M):
        for c in range(N):
            s = 0
            for k in range(K):
                s += A[r][k] * B[k][c]
            res[r][c] = s
    return res

def transpose(A):
    M, N = len(A), len(A[0])
    res = [[0]*M for _ in range(N)]
    for r in range(M):
        for c in range(N):
            res[c][r] = A[r][c]
    return res

def scale_val(val, shift_val):
    if shift_val >= 0:
        res = val << shift_val
    else:
        res = val >> (-shift_val)
    if res > 32767:
        return 32767
    elif res < -32768:
        return -32768
    return res

def scale_matrix(A, shift_val):
    M, N = len(A), len(A[0])
    res = [[0]*N for _ in range(M)]
    for r in range(M):
        for c in range(N):
            res[r][c] = scale_val(A[r][c], shift_val)
    return res

async def reset_dut(dut):
    dut.rst.value = 1
    dut.en.value = 1
    dut.start.value = 0
    dut.dataflow_mode_sel.value = 0
    dut.format_mode.value = 0
    dut.q_write_en.value = 0
    dut.q_write_addr.value = 0
    dut.q_write_data.value = 0
    dut.k_write_en.value = 0
    dut.k_write_addr.value = 0
    dut.k_write_data.value = 0
    dut.w_write_en.value = 0
    dut.w_addr_row.value = 0
    dut.w_addr_col.value = 0
    dut.w_data_in.value = 0
    dut.scale_act.value = 0
    dut.scale_weight.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)

@cocotb.test()
async def test_mx_attention_core(dut):
    # Detect N parameter from DUT
    try:
        N = int(dut.N.value)
    except Exception:
        N = 4

    dut._log.info(f"Detected array parameter N = {N}")

    # Start clock generator (100MHz / 10ns period)
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    # Apply Reset
    await reset_dut(dut)
    
    assert dut.busy.value == 0, "DUT is busy immediately after reset"
    assert dut.done.value == 0, "DUT asserts done immediately after reset"

    # Helper function to read a result matrix element dynamically
    def get_result(r, c):
        port_name = f"result_{r}{c}"
        if hasattr(dut, port_name):
            return getattr(dut, port_name).value.to_unsigned()
        else:
            flat_val = int(dut.result_flat.value)
            return (flat_val >> ((r * N + c) * 16)) & 0xFFFF

    # Setup matrices based on size
    if N == 4:
        Q = [
            [2, -1, 3, 0],
            [1, 2, 0, -2],
            [0, 1, 1, 3],
            [-3, 0, 2, 1]
        ]
        K = [
            [1, 2, 0, 1],
            [-2, 1, 3, 0],
            [-3, -1, 2, -3],
            [3, 0, -1, 2]
        ]
    else:
        Q = [[random.randint(-8, 7) for _ in range(N)] for _ in range(N)]
        K = [[random.randint(-8, 7) for _ in range(N)] for _ in range(N)]

    # Program Q and K matrices into Scratchpad SRAM
    dut._log.info("Programming Q and K matrices into Scratchpad SRAM...")
    for addr in range(N):
        dut.q_write_addr.value = addr
        dut.q_write_data.value = pack_word(Q[addr], N)
        dut.q_write_en.value = 1
        
        dut.k_write_addr.value = addr
        dut.k_write_data.value = pack_word(K[addr], N)
        dut.k_write_en.value = 1
        await RisingEdge(dut.clk)
        
    dut.q_write_en.value = 0
    dut.k_write_en.value = 0
    await RisingEdge(dut.clk)
    dut._log.info("SRAM programming completed successfully.")

    # ==================================================
    # Test Case 1: Weight-Stationary (WS) Mode
    # ==================================================
    dut._log.info("Starting Test Case 1: Weight-Stationary (WS) Mode")
    dut.dataflow_mode_sel.value = 0
    dut.format_mode.value = 0 # MXINT4
    dut.scale_act.value = 2
    dut.scale_weight.value = -1 # Total scale factor = 2^(2 - 1) = 2

    dut._log.info("Programming weights into PE cells...")
    for r in range(N):
        for c in range(N):
            dut.w_addr_row.value = r
            dut.w_addr_col.value = c
            dut.w_data_in.value = K[r][c]
            dut.w_write_en.value = 1
            await RisingEdge(dut.clk)
            
    dut.w_write_en.value = 0
    await RisingEdge(dut.clk)
    dut._log.info("PE weights programmed.")

    # Start WS Execution
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0

    # Wait for execution completion
    while dut.done.value == 0:
        await RisingEdge(dut.clk)

    await Timer(1, unit="ns")
    
    ref_ws = matmul(transpose(Q), K)
    ref_ws_scaled = scale_matrix(ref_ws, 1) # shift = +1 (multiplies by 2)
    expected_ws_softmax = [mx_softmax_unit_ref(row) for row in ref_ws_scaled]

    dut._log.info("Verifying WS results...")
    for r in range(N):
        row_str = f"WS Softmax Row {r}: "
        for c in range(N):
            val = get_result(r, c)
            row_str += f"[{val}] "
            expected_val = expected_ws_softmax[r][c]
            assert val == expected_val, f"Mismatch at WS element ({r},{c}): expected {expected_val}, got {val}"
        dut._log.info(row_str)
    dut._log.info("Weight-Stationary mode verified successfully!")

    # ==================================================
    # Test Case 2: Output-Stationary (OS) Mode
    # ==================================================
    await reset_dut(dut)
    
    dut._log.info("Reprogramming SRAM for OS Mode...")
    for addr in range(N):
        dut.q_write_addr.value = addr
        dut.q_write_data.value = pack_word(Q[addr], N)
        dut.q_write_en.value = 1
        
        dut.k_write_addr.value = addr
        dut.k_write_data.value = pack_word(K[addr], N)
        dut.k_write_en.value = 1
        await RisingEdge(dut.clk)
        
    dut.q_write_en.value = 0
    dut.k_write_en.value = 0
    await RisingEdge(dut.clk)

    dut._log.info("Starting Test Case 2: Output-Stationary (OS) Mode")
    dut.dataflow_mode_sel.value = 1
    dut.format_mode.value = 0 # MXINT4
    dut.scale_act.value = 1
    dut.scale_weight.value = 1 # Total scale factor = 2^(1 + 1) = 4

    # Start OS Execution
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0

    # Wait for execution completion
    while dut.done.value == 0:
        await RisingEdge(dut.clk)

    await Timer(1, unit="ns")

    ref_os = matmul(Q, K)
    ref_os_scaled = scale_matrix(ref_os, 2) # shift = +2 (multiplies by 4)
    expected_os_softmax = [mx_softmax_unit_ref(row) for row in ref_os_scaled]

    dut._log.info("Verifying OS results...")
    for r in range(N):
        row_str = f"OS Softmax Row {r}: "
        for c in range(N):
            val = get_result(r, c)
            row_str += f"[{val}] "
            expected_val = expected_os_softmax[r][c]
            assert val == expected_val, f"Mismatch at OS element ({r},{c}): expected {expected_val}, got {val}"
        dut._log.info(row_str)
    dut._log.info("Output-Stationary mode verified successfully!")

@cocotb.test()
async def test_mx_attention_core_fp8(dut):
    try:
        N = int(dut.N.value)
    except Exception:
        N = 4

    # Start clock generator if not already running
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    # We will test both FP8 formats: E4M3 (mode 2) and E5M2 (mode 3)
    for format_mode in [2, 3]:
        dut._log.info(f"--- Running FP8 Verification for Mode {format_mode} ---")
        await reset_dut(dut)
        dut.format_mode.value = format_mode

        # Generate random values representable in the format
        # For simplicity, generate valid random binary values (8 bits)
        Q_bin = [[random.randint(0, 255) for _ in range(N)] for _ in range(N)]
        K_bin = [[random.randint(0, 255) for _ in range(N)] for _ in range(N)]

        # Program SRAM
        for addr in range(N):
            dut.q_write_addr.value = addr
            dut.q_write_data.value = pack_word(Q_bin[addr], N)
            dut.q_write_en.value = 1
            
            dut.k_write_addr.value = addr
            dut.k_write_data.value = pack_word(K_bin[addr], N)
            dut.k_write_en.value = 1
            await RisingEdge(dut.clk)
            
        dut.q_write_en.value = 0
        dut.k_write_en.value = 0
        await RisingEdge(dut.clk)

        # Reference float calculation
        # Compute Q^T x K
        float_Q = [[to_float(x, format_mode) for x in row] for row in Q_bin]
        float_K = [[to_float(x, format_mode) for x in row] for row in K_bin]
        
        # Matrix multiplication
        ref_float = [[0.0]*N for _ in range(N)]
        for r in range(N):
            for c in range(N):
                ref_float[r][c] = sum(float_Q[k][r] * float_K[k][c] for k in range(N))

        # We set scale factors: scale_act + scale_weight
        # To get Q4.12 outputs, we need shift = 12 - mant_frac
        # E4M3 (mode 2) has mant_frac = 3, so shift = 9
        # E5M2 (mode 3) has mant_frac = 2, so shift = 10
        mant_frac = 3 if format_mode == 2 else 2
        total_shift = 12 - mant_frac
        
        # Program scale factors
        dut.scale_act.value = total_shift // 2
        dut.scale_weight.value = total_shift - (total_shift // 2)
        dut.dataflow_mode_sel.value = 0 # WS Mode

        # Load static weights K into PEs
        for r in range(N):
            for c in range(N):
                dut.w_addr_row.value = r
                dut.w_addr_col.value = c
                dut.w_data_in.value = K_bin[r][c]
                dut.w_write_en.value = 1
                await RisingEdge(dut.clk)
        dut.w_write_en.value = 0
        await RisingEdge(dut.clk)

        # Start execution
        dut.start.value = 1
        await RisingEdge(dut.clk)
        dut.start.value = 0

        # Wait for done
        while dut.done.value == 0:
            await RisingEdge(dut.clk)
        await Timer(1, unit="ns")

        # Fixed point reference mapping
        ref_scaled = [[0]*N for _ in range(N)]
        for r in range(N):
            for c in range(N):
                scaled = float_ref_scaled = ref_float[r][c] * (2.0 ** total_shift) * (2.0 ** mant_frac)
                val_int = int(round(scaled))
                if val_int > 32767:
                    ref_scaled[r][c] = 32767
                elif val_int < -32768:
                    ref_scaled[r][c] = -32768
                else:
                    ref_scaled[r][c] = val_int

        expected_softmax = [mx_softmax_unit_ref(row) for row in ref_scaled]

        # Verify results
        for r in range(N):
            row_str = f"FP8 Mode {format_mode} Row {r}: "
            for c in range(N):
                port_name = f"result_{r}{c}"
                if hasattr(dut, port_name):
                    val = getattr(dut, port_name).value.to_unsigned()
                else:
                    flat_val = int(dut.result_flat.value)
                    val = (flat_val >> ((r * N + c) * 16)) & 0xFFFF
                row_str += f"[{val}] "
                expected_val = expected_softmax[r][c]
                # Allow a small rounding tolerance of +/- 1 LSB due to differences in python/verilog intermediate roundings
                assert abs(val - expected_val) <= 1, f"Mismatch at ({r},{c}): expected {expected_val}, got {val}"
            dut._log.info(row_str)
        dut._log.info(f"FP8 format mode {format_mode} verified successfully!")
