# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

@cocotb.test()
async def test_i2c_protocol(dut):
    dut._log.info("Start I2C Protocol Test")
    
    # Set the clock period to 10 ns (100 MHz)
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    # Reset
    dut._log.info("Reset")
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 2)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)
    
    # Write test: addr=0x2A, data=0x55
    dut._log.info("Write Test - addr=0x2A, data=0x55")
    dut.ui_in.value = 0b10101010  # addr[6:0] + enable[7] = 1
    dut.uio_in.value = 0x55       # write data
    await ClockCycles(dut.clk, 2)
    dut.ui_in.value = 0b00101010  # disable
    await ClockCycles(dut.clk, 10)
    
    # Read test: addr=0x2A
    dut._log.info("Read Test - addr=0x2A")
    dut.ui_in.value = 0b00101010  # addr[6:0], enable=0
    dut.uio_in.value = 0x80       # R/W=1 for read
    await ClockCycles(dut.clk, 1)
    dut.ui_in.value = 0b10101010  # enable
    await ClockCycles(dut.clk, 2)
    dut.ui_in.value = 0b00101010  # disable
    await ClockCycles(dut.clk, 10)
    
    dut._log.info(f"Read output: {dut.uo_out.value}")
    dut._log.info("Test Complete")
