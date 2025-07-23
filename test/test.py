# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, FallingEdge, Timer
from cocotb.types import LogicArray

@cocotb.test()
async def test_i2c_controller(dut):
    """Test the I2C controller functionality"""
    
    dut._log.info("Starting I2C Controller Test")
    
    # Set the clock period to 10 ns (100 MHz) - faster for I2C timing
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    # Reset sequence
    dut._log.info("Performing Reset")
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 10)
    
    # Wait for I2C controller to be ready
    dut._log.info("Waiting for I2C controller to be ready")
    timeout = 0
    while dut.uio_out.value[1] != 1 and timeout < 1000:  # Check ready bit
        await ClockCycles(dut.clk, 1)
        timeout += 1
    
    if timeout >= 1000:
        dut._log.error("Timeout waiting for I2C ready signal")
        assert False, "I2C controller not ready"
    
    dut._log.info("I2C controller is ready")
    
    # Test Case 1: I2C Write Operation
    dut._log.info("Test Case 1: I2C Write Operation")
    
    # Set up write transaction
    slave_addr = 0b0101010  # 7-bit slave address (0x2A)
    write_data = 0x55
    
    # Configure inputs for write operation
    dut.ui_in.value = slave_addr  # Address in bits [6:0], enable in bit [7]
    dut.uio_in.value = write_data  # Data to write, R/W bit = 0 (write)
    
    await ClockCycles(dut.clk, 2)
    
    # Start transaction by asserting enable
    dut.ui_in.value = (1 << 7) | slave_addr  # Set enable bit
    await ClockCycles(dut.clk, 2)
    
    # Clear enable
    dut.ui_in.value = slave_addr
    
    # Wait for transaction to start (ready goes low)
    dut._log.info("Waiting for I2C transaction to start")
    timeout = 0
    while dut.uio_out.value[1] == 1 and timeout < 100:  # Wait for not ready
        await ClockCycles(dut.clk, 1)
        timeout += 1
    
    # Wait for transaction to complete (ready goes high again)
    dut._log.info("Waiting for I2C write transaction to complete")
    timeout = 0
    while dut.uio_out.value[1] != 1 and timeout < 1000:  # Wait for ready
        await ClockCycles(dut.clk, 1)
        timeout += 1
        
    if timeout >= 1000:
        dut._log.error("Timeout waiting for I2C write completion")
        assert False, "I2C write transaction timeout"
    
    dut._log.info(f"I2C write completed - wrote 0x{write_data:02x} to address 0x{slave_addr:02x}")
    
    # Test Case 2: I2C Read Operation
    dut._log.info("Test Case 2: I2C Read Operation")
    
    # Set up read transaction
    dut.ui_in.value = slave_addr  # Address
    dut.uio_in.value = 0x80  # R/W bit = 1 (read) in bit 7
    
    await ClockCycles(dut.clk, 2)
    
    # Start transaction
    dut.ui_in.value = (1 << 7) | slave_addr  # Set enable bit
    await ClockCycles(dut.clk, 2)
    
    # Clear enable
    dut.ui_in.value = slave_addr
    
    # Wait for transaction to start
    timeout = 0
    while dut.uio_out.value[1] == 1 and timeout < 100:
        await ClockCycles(dut.clk, 1)
        timeout += 1
    
    # Wait for transaction to complete
    dut._log.info("Waiting for I2C read transaction to complete")
    timeout = 0
    while dut.uio_out.value[1] != 1 and timeout < 1000:
        await ClockCycles(dut.clk, 1)
        timeout += 1
        
    if timeout >= 1000:
        dut._log.error("Timeout waiting for I2C read completion")
        assert False, "I2C read transaction timeout"
    
    # Check read data
    read_data = int(dut.uo_out.value)
    dut._log.info(f"I2C read completed - read 0x{read_data:02x} from address 0x{slave_addr:02x}")
    
    # The slave returns 0xCC (11001100) as default data
    expected_data = 0xCC
    assert read_data == expected_data, f"Expected 0x{expected_data:02x}, got 0x{read_data:02x}"
    
    # Test Case 3: Invalid Address (should get NACK)
    dut._log.info("Test Case 3: I2C Write to Invalid Address")
    
    invalid_addr = 0b1010101  # Different address
    test_data = 0xAA
    
    dut.ui_in.value = invalid_addr
    dut.uio_in.value = test_data
    
    await ClockCycles(dut.clk, 2)
    
    # Start transaction
    dut.ui_in.value = (1 << 7) | invalid_addr
    await ClockCycles(dut.clk, 2)
    
    # Clear enable
    dut.ui_in.value = invalid_addr
    
    # Wait for transaction to start
    timeout = 0
    while dut.uio_out.value[1] == 1 and timeout < 100:
        await ClockCycles(dut.clk, 1)
        timeout += 1
    
    # Wait for transaction to complete (should be quick due to NACK)
    dut._log.info("Waiting for I2C invalid address transaction to complete")
    timeout = 0
    while dut.uio_out.value[1] != 1 and timeout < 1000:
        await ClockCycles(dut.clk, 1)
        timeout += 1
        
    if timeout >= 1000:
        dut._log.error("Timeout waiting for I2C invalid address transaction")
        assert False, "I2C invalid address transaction timeout"
    
    dut._log.info(f"I2C transaction to invalid address completed (expected NACK)")
    
    # Test Case 4: Multiple Write Operations
    dut._log.info("Test Case 4: Multiple I2C Write Operations")
    
    test_values = [0x00, 0xFF, 0xA5, 0x5A]
    
    for i, test_val in enumerate(test_values):
        dut._log.info(f"Write operation {i+1}/4: writing 0x{test_val:02x}")
        
        # Set up write transaction
        dut.ui_in.value = slave_addr
        dut.uio_in.value = test_val
        
        await ClockCycles(dut.clk, 2)
        
        # Start transaction
        dut.ui_in.value = (1 << 7) | slave_addr
        await ClockCycles(dut.clk, 2)
        
        # Clear enable
        dut.ui_in.value = slave_addr
        
        # Wait for completion
        timeout = 0
        while dut.uio_out.value[1] == 1 and timeout < 100:
            await ClockCycles(dut.clk, 1)
            timeout += 1
            
        timeout = 0
        while dut.uio_out.value[1] != 1 and timeout < 1000:
            await ClockCycles(dut.clk, 1)
            timeout += 1
            
        if timeout >= 1000:
            dut._log.error(f"Timeout on write operation {i+1}")
            assert False, f"Write operation {i+1} timeout"
    
    dut._log.info("All I2C tests passed successfully!")
    
    # Additional delay to observe final state
    await ClockCycles(dut.clk, 10)


@cocotb.test()
async def test_reset_behavior(dut):
    """Test reset behavior of the I2C controller"""
    
    dut._log.info("Testing Reset Behavior")
    
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    # Test reset during operation
    dut.ena.value = 1
    dut.ui_in.value = 0x2A  # Valid address
    dut.uio_in.value = 0x55
    dut.rst_n.value = 1
    
    await ClockCycles(dut.clk, 10)
    
    # Start a transaction
    dut.ui_in.value = (1 << 7) | 0x2A
    await ClockCycles(dut.clk, 5)
    
    # Assert reset during transaction
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    
    # Check that outputs are in reset state
    # After reset, the controller should not be ready initially
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 10)
    
    # Wait for ready signal to come back
    timeout = 0
    while dut.uio_out.value[1] != 1 and timeout < 1000:
        await ClockCycles(dut.clk, 1)
        timeout += 1
    
    assert timeout < 1000, "Controller did not recover from reset"
    dut._log.info("Reset behavior test passed")


@cocotb.test() 
async def test_signal_integrity(dut):
    """Test signal integrity and edge cases"""
    
    dut._log.info("Testing Signal Integrity")
    
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
    
    # Test that uio_oe bits are set correctly
    uio_oe = int(dut.uio_oe.value)
    dut._log.info(f"uio_oe value: 0x{uio_oe:02x}")
    
    # Check that SDA and SCL enable bits are set (bits 1:0 should be 11)
    assert (uio_oe & 0x03) == 0x03, f"Expected uio_oe[1:0] = 11, got {uio_oe & 0x03:02b}"
    
    # Check that other bits are 0
    assert (uio_oe & 0xFC) == 0x00, f"Expected uio_oe[7:2] = 000000, got {(uio_oe & 0xFC) >> 2:06b}"
    
    dut._log.info("Signal integrity test passed")
