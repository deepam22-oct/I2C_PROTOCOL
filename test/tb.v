`default_nettype none
`timescale 1ns / 1ps

module tb ();
  // VCD dump
  initial begin
    $dumpfile("tb.vcd");
    $dumpvars(0, tb);
  end
  
  // Signals
  reg clk = 0;
  reg rst_n;
  reg ena = 1;
  reg [7:0] ui_in;
  reg [7:0] uio_in;
  wire [7:0] uo_out;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;
  
  // DUT
  tt_um_example user_project (
      .ui_in(ui_in), .uo_out(uo_out), .uio_in(uio_in), 
      .uio_out(uio_out), .uio_oe(uio_oe), .ena(ena), 
      .clk(clk), .rst_n(rst_n)
  );
  
  // 100MHz clock
  always #5 clk = ~clk;
  
  // Test
  initial begin
    // Reset
    rst_n = 0; ui_in = 0; uio_in = 0;
    #20 rst_n = 1;
    #20;
    
    // Write test: addr=0x2A, data=0x55
    ui_in = 8'b10101010;  // addr[6:0] + enable[7]
    uio_in = 8'h55;       // write data
    #20 ui_in[7] = 0;     // disable
    #100;
    
    // Read test: addr=0x2A
    ui_in = 8'b00101010;  // addr[6:0], enable=0
    uio_in = 8'h80;       // R/W=1 for read
    #10 ui_in[7] = 1;     // enable
    #20 ui_in[7] = 0;     // disable
    #100;
    
    $display("Test complete");
  //  $finish;
  end
  
endmodule
