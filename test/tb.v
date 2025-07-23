`default_nettype none
`timescale 1ns / 1ps

/* This testbench instantiates the I2C controller module and provides
   convenient wires that can be driven / tested by the cocotb test.py.
*/
module tb ();
  // Dump the signals to a VCD file. You can view it with gtkwave or surfer.
  initial begin
    $dumpfile("tb.vcd");
    $dumpvars(0, tb);
    #1;
  end

  // Wire up the inputs and outputs:
  reg clk;
  reg rst_n;
  reg ena;
  reg [7:0] ui_in;
  reg [7:0] uio_in;
  wire [7:0] uo_out;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;

  // I2C specific signals for easier testing
  wire [6:0] i2c_addr = ui_in[6:0];
  wire i2c_enable = ui_in[7];
  wire [7:0] i2c_data_in = uio_in[7:0];
  wire [7:0] i2c_data_out = uo_out[7:0];
  wire i2c_ready = uio_out[1];

  // Replace tt_um_example with your module name:
  tt_um_example user_project (
      .ui_in  (ui_in),    // Dedicated inputs
      .uo_out (uo_out),   // Dedicated outputs
      .uio_in (uio_in),   // IOs: Input path
      .uio_out(uio_out),  // IOs: Output path
      .uio_oe (uio_oe),   // IOs: Enable path (active high: 0=input, 1=output)
      .ena    (ena),      // enable - goes high when design is selected
      .clk    (clk),      // clock
      .rst_n  (rst_n)     // not reset
  );

  // Clock generation
  initial begin
    clk = 0;
    forever #5 clk = ~clk; // 100MHz clock (10ns period)
  end

  // Test sequence
  initial begin
    // Initialize signals
    rst_n = 0;
    ena = 1;
    ui_in = 8'h00;
    uio_in = 8'h00;
    
    // Reset sequence
    #20;
    rst_n = 1;
    #20;
    
    // Wait for ready
    wait(i2c_ready == 1);
    #10;
    
    // Test Case 1: Write operation to slave address 0x2A (0101010)
    $display("Test Case 1: I2C Write Operation");
    ui_in[6:0] = 7'b0101010; // Slave address
    ui_in[7] = 0;            // Enable = 0 initially
    uio_in = 8'h55;          // Data to write
    #10;
    ui_in[7] = 1;            // Enable transaction
    #10;
    ui_in[7] = 0;            // Disable enable signal
    
    // Wait for transaction to complete
    wait(i2c_ready == 0);    // Wait for busy
    wait(i2c_ready == 1);    // Wait for ready again
    #20;
    
    // Test Case 2: Read operation from slave address 0x2A
    $display("Test Case 2: I2C Read Operation");
    ui_in[6:0] = 7'b0101010; // Slave address
    ui_in[7] = 0;            // Enable = 0 initially  
    uio_in[7] = 1;           // R/W bit = 1 for read
    uio_in[6:0] = 7'h00;     // Don't care for read data
    #10;
    ui_in[7] = 1;            // Enable transaction
    #10;
    ui_in[7] = 0;            // Disable enable signal
    
    // Wait for transaction to complete
    wait(i2c_ready == 0);    // Wait for busy
    wait(i2c_ready == 1);    // Wait for ready again
    #20;
    
    $display("Read data: 0x%h", i2c_data_out);
    
    // Test Case 3: Write to different address (should get NACK)
    $display("Test Case 3: I2C Write to invalid address");
    ui_in[6:0] = 7'b1010101; // Different slave address
    ui_in[7] = 0;            // Enable = 0 initially
    uio_in = 8'hAA;          // Data to write
    #10;
    ui_in[7] = 1;            // Enable transaction
    #10;
    ui_in[7] = 0;            // Disable enable signal
    
    // Wait for transaction to complete
    wait(i2c_ready == 0);    // Wait for busy
    wait(i2c_ready == 1);    // Wait for ready again
    #20;
    
    // Additional wait time to observe waveforms
    #100;
    
    $display("Testbench completed");
    $finish;
  end

  // Monitor important signals
  always @(posedge clk) begin
    if (i2c_enable) begin
      $display("Time: %0t, I2C Transaction Started - Addr: 0x%h, Data: 0x%h, R/W: %b", 
               $time, i2c_addr, i2c_data_in, uio_in[7]);
    end
    if (i2c_ready && $past(!i2c_ready)) begin
      $display("Time: %0t, I2C Transaction Completed - Data Out: 0x%h", 
               $time, i2c_data_out);
    end
  end

endmodule
