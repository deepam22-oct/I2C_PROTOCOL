# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

@cocotb.test()
async def test_i2c_basic(dut):
    """Basic I2C controller test"""
    
    # 100 MHz clock
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    # Reset
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 10)
    
    # Wait for ready
    while dut.uio_out.value[1] != 1:
        await ClockCycles(dut.clk, 1)
    
    # Write test
    slave_addr = 0x2A
    write_data = 0x55
    
    dut.ui_in.value = slave_addr
    dut.uio_in.value = write_data
    await ClockCycles(dut.clk, 2)
    
    # Enable transaction
    dut.ui_in.value = (1 << 7) | slave_addr
    await ClockCycles(dut.clk, 2)
    dut.ui_in.value = slave_addr
    
    # Wait for completion
    while dut.uio_out.value[1] == 1:  # Wait for busy
        await ClockCycles(dut.clk, 1)
    while dut.uio_out.value[1] != 1:  # Wait for ready
        await ClockCycles(dut.clk, 1)
    
    # Read test
    dut.ui_in.value = slave_addr
    dut.uio_in.value = 0x80  # R/W = 1
    await ClockCycles(dut.clk, 2)
    
    # Enable transaction
    dut.ui_in.value = (1 << 7) | slave_addr
    await ClockCycles(dut.clk, 2)
    dut.ui_in.value = slave_addr
    
    # Wait for completion
    while dut.uio_out.value[1] == 1:
        await ClockCycles(dut.clk, 1)
    while dut.uio_out.value[1] != 1:
        await ClockCycles(dut.clk, 1)
    
    # Check read data
    read_data = int(dut.uo_out.value)
    assert read_data == 0xCC, f"Expected 0xCC, got 0x{read_data:02x}"
    
    print("I2C test passed")

@cocotb.test()
async def test_reset(dut):
    """Test reset functionality"""
    
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    # Test reset
    dut.ena.value = 1
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 10)
    
    # Check ready signal
    timeout = 100
    while dut.uio_out.value[1] != 1 and timeout > 0:
        await ClockCycles(dut.clk, 1)
        timeout -= 1
    
    assert timeout > 0, "Reset recovery failed"
    print("Reset test passed")
