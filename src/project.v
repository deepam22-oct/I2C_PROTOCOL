/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none
`timescale 1ns / 1ps

module tt_um_example (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    // Internal signals
    wire rst = ~rst_n;  // Convert active-low reset to active-high
    wire [6:0] addr;
    wire [7:0] data_in;
    wire enable;
    wire rw;
    wire [7:0] data_out;
    wire ready;
    
    // I2C signals
    wire sda_out, sda_in, sda_oe;
    wire scl_out, scl_in, scl_oe;
    
    // Input mapping
    assign addr = ui_in[6:0];        // 7-bit I2C address from ui_in[6:0]
    assign enable = ui_in[7];        // Enable signal from ui_in[7]
    assign data_in = uio_in[7:0];    // 8-bit data input from uio_in
    assign rw = uio_in[7];           // Read/Write bit from uio_in[7]
    
    // Output mapping
    assign uo_out = data_out;        // I2C read data output
    
    // Bidirectional IO configuration
    assign uio_oe[0] = sda_oe;       // SDA output enable
    assign uio_oe[1] = scl_oe;       // SCL output enable
    assign uio_oe[7:2] = 6'b000000;  // Other uio pins as inputs
    
    assign uio_out[0] = sda_out;     // SDA output
    assign uio_out[1] = scl_out;     // SCL output  
    assign uio_out[7:2] = {5'b00000, ready}; // Ready signal on uio_out[7]
    
    assign sda_in = uio_in[0];       // SDA input
    assign scl_in = uio_in[1];       // SCL input
    
    // Instantiate the I2C top module
    i2c_top i2c_system (
        .clk(clk),
        .rst(rst),
        .addr(addr),
        .data_in(data_in),
        .enable(enable),
        .rw(rw),
        .data_out(data_out),
        .ready(ready),
        .sda_in(sda_in),
        .sda_out(sda_out),
        .sda_oe(sda_oe),
        .scl_in(scl_in),
        .scl_out(scl_out),
        .scl_oe(scl_oe)
    );

    // List all unused inputs to prevent warnings
    wire _unused = &{ena, 1'b0};

endmodule

module i2c_top(
    input wire clk,
    input wire rst,
    input wire [6:0] addr,
    input wire [7:0] data_in,
    input wire enable,
    input wire rw,

    output wire [7:0] data_out,
    output wire ready,

    input wire sda_in,
    output wire sda_out,
    output wire sda_oe,
    input wire scl_in,
    output wire scl_out,
    output wire scl_oe
);
   
    // Internal I2C bus signals
    wire i2c_sda_master, i2c_scl_master;
    wire i2c_sda_slave, i2c_scl_slave;
    wire master_sda_oe, master_scl_oe;
    wire slave_sda_oe, slave_scl_oe;
    
    // Bus arbitration (simplified - master has priority)
    assign sda_out = master_sda_oe ? i2c_sda_master : (slave_sda_oe ? i2c_sda_slave : 1'b1);
    assign scl_out = master_scl_oe ? i2c_scl_master : 1'b1;
    assign sda_oe = master_sda_oe | slave_sda_oe;
    assign scl_oe = master_scl_oe;
   
    i2c_controller master (
        .clk(clk), 
        .rst(rst), 
        .addr(addr), 
        .data_in(data_in), 
        .enable(enable), 
        .rw(rw), 
        .data_out(data_out), 
        .ready(ready), 
        .sda_in(sda_in),
        .sda_out(i2c_sda_master),
        .sda_oe(master_sda_oe),
        .scl_in(scl_in),
        .scl_out(i2c_scl_master),
        .scl_oe(master_scl_oe)
    );
    
    i2c_slave_controller #(7'b0101010) slave1 (
        .clk(clk),
        .rst(rst),
        .sda_in(sda_in),
        .sda_out(i2c_sda_slave),
        .sda_oe(slave_sda_oe),
        .scl_in(scl_in)
    );
endmodule

// Master Controller
module i2c_controller(
    input wire clk,
    input wire rst,
    input wire [6:0] addr,
    input wire [7:0] data_in,
    input wire enable,
    input wire rw,

    output reg [7:0] data_out,
    output wire ready,

    input wire sda_in,
    output reg sda_out,
    output reg sda_oe,
    input wire scl_in,
    output reg scl_out,
    output reg scl_oe
);

    localparam IDLE = 0;
    localparam START = 1;
    localparam ADDRESS = 2;
    localparam READ_ACK = 3;
    localparam WRITE_DATA = 4;
    localparam WRITE_ACK = 5;
    localparam READ_DATA = 6;
    localparam READ_ACK2 = 7;
    localparam STOP = 8;
    
    localparam DIVIDE_BY = 4;

    reg [7:0] state;
    reg [7:0] saved_addr;
    reg [7:0] saved_data;
    reg [7:0] counter;
    reg [7:0] counter2;
    reg i2c_clk;

    assign ready = ((rst == 0) && (state == IDLE)) ? 1 : 0;
    
    // Clock generation
    always @(posedge clk) begin
        if (rst) begin
            counter2 <= 0;
            i2c_clk <= 1;
        end else begin
            if (counter2 == (DIVIDE_BY/2) - 1) begin
                i2c_clk <= ~i2c_clk;
                counter2 <= 0;
            end else begin
                counter2 <= counter2 + 1;
            end
        end
    end 
    
    // Main state machine
    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            sda_out <= 1;
            sda_oe <= 1;
            scl_out <= 1;
            scl_oe <= 0;
            counter <= 0;
            saved_addr <= 0;
            saved_data <= 0;
            data_out <= 0;
        end else begin
            case(state)
                IDLE: begin
                    sda_out <= 1;
                    sda_oe <= 1;
                    scl_out <= 1;
                    scl_oe <= 0;
                    if (enable) begin
                        state <= START;
                        saved_addr <= {addr, rw};
                        saved_data <= data_in;
                    end
                end

                START: begin
                    sda_out <= 0;  // START condition
                    sda_oe <= 1;
                    scl_out <= 1;
                    scl_oe <= 1;
                    counter <= 7;
                    state <= ADDRESS;
                end

                ADDRESS: begin
                    scl_out <= i2c_clk;
                    scl_oe <= 1;
                    sda_out <= saved_addr[counter];
                    sda_oe <= 1;
                    if (i2c_clk == 0) begin  // Update on falling edge
                        if (counter == 0) begin 
                            state <= READ_ACK;
                        end else begin
                            counter <= counter - 1;
                        end
                    end
                end

                READ_ACK: begin
                    scl_out <= i2c_clk;
                    scl_oe <= 1;
                    sda_oe <= 0;  // Release SDA for ACK
                    if (i2c_clk == 1) begin  // Sample on rising edge
                        if (sda_in == 0) begin
                            counter <= 7;
                            if(saved_addr[0] == 0) begin
                                state <= WRITE_DATA;
                            end else begin
                                state <= READ_DATA;
                            end
                        end else begin
                            state <= STOP;
                        end
                    end
                end

                WRITE_DATA: begin
                    scl_out <= i2c_clk;
                    scl_oe <= 1;
                    sda_out <= saved_data[counter];
                    sda_oe <= 1;
                    if (i2c_clk == 0) begin
                        if(counter == 0) begin
                            state <= READ_ACK2;
                        end else begin
                            counter <= counter - 1;
                        end
                    end
                end
                
                READ_ACK2: begin
                    scl_out <= i2c_clk;
                    scl_oe <= 1;
                    sda_oe <= 0;
                    if (i2c_clk == 1) begin
                        if ((sda_in == 0) && (enable == 1)) begin
                            state <= IDLE;
                        end else begin
                            state <= STOP;
                        end
                    end
                end

                READ_DATA: begin
                    scl_out <= i2c_clk;
                    scl_oe <= 1;
                    sda_oe <= 0;
                    if (i2c_clk == 1) begin  // Sample on rising edge
                        data_out[counter] <= sda_in;
                        if (counter == 0) begin
                            state <= WRITE_ACK;
                        end else begin
                            counter <= counter - 1;
                        end
                    end
                end
                
                WRITE_ACK: begin
                    scl_out <= i2c_clk;
                    scl_oe <= 1;
                    sda_out <= 0;  // Send ACK
                    sda_oe <= 1;
                    if (i2c_clk == 0) begin
                        state <= STOP;
                    end
                end

                STOP: begin
                    scl_out <= 1;
                    scl_oe <= 1;
                    sda_out <= 1;  // STOP condition
                    sda_oe <= 1;
                    state <= IDLE;
                end
                
                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule

// Slave Controller
module i2c_slave_controller #(parameter ADDRESS = 7'b0101010)(
    input wire clk,
    input wire rst,
    input wire sda_in,
    output reg sda_out,
    output reg sda_oe,
    input wire scl_in
);
        
    localparam READ_ADDR = 0;
    localparam SEND_ACK = 1;
    localparam READ_DATA = 2;
    localparam WRITE_DATA = 3;
    localparam SEND_ACK2 = 4;
    
    reg [7:0] addr;
    reg [7:0] counter;
    reg [7:0] state;
    reg [7:0] data_in;
    reg [7:0] data_out;
    reg start;
    reg scl_prev;
    reg sda_prev;
    
    always @(posedge clk) begin
        if (rst) begin
            addr <= 0;
            counter <= 0;
            state <= READ_ADDR;
            data_in <= 0;
            data_out <= 8'b11001100;
            sda_out <= 0;
            sda_oe <= 0;
            start <= 0;
            scl_prev <= 1;
            sda_prev <= 1;
        end else begin
            scl_prev <= scl_in;
            sda_prev <= sda_in;
            
            // Detect START condition
            if ((sda_prev == 1) && (sda_in == 0) && (scl_in == 1) && (start == 0)) begin
                start <= 1;        
                counter <= 7;
                state <= READ_ADDR;
                sda_oe <= 0;
            end
            
            // Detect STOP condition
            if ((sda_prev == 0) && (sda_in == 1) && (scl_in == 1) && (start == 1)) begin
                state <= READ_ADDR;
                start <= 0;
                sda_oe <= 0;
            end
            
            // Rising edge of SCL
            if ((scl_prev == 0) && (scl_in == 1) && (start == 1)) begin
                case(state)
                    READ_ADDR: begin
                        addr[counter] <= sda_in;
                        if(counter == 0) begin
                            state <= SEND_ACK;
                        end else begin
                            counter <= counter - 1;
                        end
                    end
                    
                    SEND_ACK: begin
                        if(addr[7:1] == ADDRESS) begin
                            counter <= 7;
                            if(addr[0] == 0) begin 
                                state <= READ_DATA;
                            end else begin
                                state <= WRITE_DATA;
                            end
                        end else begin
                            start <= 0;
                            state <= READ_ADDR;
                        end
                    end
                    
                    READ_DATA: begin
                        data_in[counter] <= sda_in;
                        if(counter == 0) begin
                            state <= SEND_ACK2;
                        end else begin
                            counter <= counter - 1;
                        end
                    end
                    
                    SEND_ACK2: begin
                        state <= READ_ADDR;                                        
                    end
                    
                    WRITE_DATA: begin
                        if(counter == 0) begin
                            state <= READ_ADDR;
                        end else begin
                            counter <= counter - 1;
                        end
                    end
                endcase
            end
            
            // Falling edge of SCL - set outputs
            if ((scl_prev == 1) && (scl_in == 0) && (start == 1)) begin
                case(state)
                    READ_ADDR: begin
                        sda_oe <= 0;                        
                    end
                    
                    SEND_ACK: begin
                        if(addr[7:1] == ADDRESS) begin
                            sda_out <= 0;
                            sda_oe <= 1;
                        end else begin
                            sda_oe <= 0;
                        end
                    end
                    
                    READ_DATA: begin
                        sda_oe <= 0;
                    end
                    
                    WRITE_DATA: begin
                        sda_out <= data_out[counter];
                        sda_oe <= 1;
                    end
                    
                    SEND_ACK2: begin
                        sda_out <= 0;
                        sda_oe <= 1;
                    end
                endcase
            end
        end
    end
endmodule
