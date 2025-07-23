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
    
    // I2C signals - using bidirectional IOs
    wire i2c_sda, i2c_scl;
    
    // Input mapping
    assign addr = ui_in[6:0];        // 7-bit I2C address from ui_in[6:0]
    assign enable = ui_in[7];        // Enable signal from ui_in[7]
    assign data_in = uio_in;         // 8-bit data input from uio_in
    assign rw = uio_in[7];           // Read/Write bit from uio_in[7] (can also be from ui_in if preferred)
    
    // Output mapping
    assign uo_out = data_out;        // I2C read data output
    
    // Bidirectional IO configuration
    // uio[0] = SDA, uio[1] = SCL
    assign uio_oe[1:0] = 2'b11;      // Enable SDA and SCL as outputs (they'll be tri-stated internally)
    assign uio_oe[7:2] = 6'b000000;  // Other uio pins as inputs
    assign uio_out[7:2] = 6'b000000; // Unused outputs set to 0
    assign uio_out[1] = ready;       // Ready signal on uio_out[1] 
    assign uio_out[0] = 1'b0;        // uio_out[0] controlled by I2C
    
    // I2C signal connections to bidirectional pins
    // Note: For TinyTapeout, we need to be careful about bidirectional signals
    // The actual I2C lines will be external, but we'll connect through the IO pins
    assign i2c_sda = 1'bz;  // This will be controlled by the I2C modules
    assign i2c_scl = 1'bz;  // This will be controlled by the I2C modules
    
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
        .i2c_sda(i2c_sda),
        .i2c_scl(i2c_scl)
    );

    // List all unused inputs to prevent warnings
    wire _unused = &{ena, 1'b0};

endmodule

// Your I2C modules below (unchanged)

module i2c_top(
    input wire clk,
    input wire rst,
    input wire [6:0] addr,
    input wire [7:0] data_in,
    input wire enable,
    input wire rw,

    output wire [7:0] data_out,
    output wire ready,

    inout wire i2c_sda,
    inout wire i2c_scl);
   
   
  i2c_controller master (
            .clk(clk), 
            .rst(rst), 
            .addr(addr), 
            .data_in(data_in), 
            .enable(enable), 
            .rw(rw), 
            .data_out(data_out), 
            .ready(ready), 
            .i2c_sda(i2c_sda), 
            .i2c_scl(i2c_scl)
        );
  i2c_slave_controller #(7'b0101010) slave1 (
            .sda(i2c_sda),
            .scl(i2c_scl)
        );
endmodule

// Master 

module i2c_controller(
        input wire clk,
        input wire rst,
        input wire [6:0] addr,
        input wire [7:0] data_in,
        input wire enable,
        input wire rw,

        output reg [7:0] data_out,
        output wire ready,

        inout i2c_sda,
        inout wire i2c_scl
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
        reg [7:0] counter2 = 0;
        reg write_enable;
        reg sda_out;
        reg i2c_scl_enable = 0;
        reg i2c_clk = 1;

        assign ready = ((rst == 0) && (state == IDLE)) ? 1 : 0;
        assign i2c_scl = (i2c_scl_enable == 0 ) ? 1 : i2c_clk;
        assign i2c_sda = (write_enable == 1) ? sda_out : 'bz;
        
        always @(posedge clk) begin
                if (counter2 == (DIVIDE_BY/2) - 1) begin
                        i2c_clk <= ~i2c_clk;
                        counter2 <= 0;
                end
                else counter2 <= counter2 + 1;
        end 
        
        always @(negedge i2c_clk, posedge rst) begin
                if(rst == 1) begin
                        i2c_scl_enable <= 0;
                end else begin
                        if ((state == IDLE) || (state == START) || (state == STOP)) begin
                                i2c_scl_enable <= 0;
                        end else begin
                                i2c_scl_enable <= 1;
                        end
                end
        
        end


        always @(posedge i2c_clk, posedge rst) begin
                if(rst == 1) begin
                        state <= IDLE;
                end                
                else begin
                        case(state)
                        
                                IDLE: begin
                                        if (enable) begin
                                                state <= START;
                                                saved_addr <= {addr, rw};
                                                saved_data <= data_in;
                                        end
                                        else state <= IDLE;
                                end

                                START: begin
                                        counter <= 7;
                                        state <= ADDRESS;
                                end

                                ADDRESS: begin
                                        if (counter == 0) begin 
                                                state <= READ_ACK;
                                        end else counter <= counter - 1;
                                end

                                READ_ACK: begin
                                        if (i2c_sda == 0) begin
                                                counter <= 7;
                                                if(saved_addr[0] == 0) state <= WRITE_DATA;
                                                else state <= READ_DATA;
                                        end else state <= STOP;
                                end

                                WRITE_DATA: begin
                                        if(counter == 0) begin
                                                state <= READ_ACK2;
                                        end else counter <= counter - 1;
                                end
                                
                                READ_ACK2: begin
                                        if ((i2c_sda == 0) && (enable == 1)) state <= IDLE;
                                        else state <= STOP;
                                end

                                READ_DATA: begin
                                        data_out[counter] <= i2c_sda;
                                        if (counter == 0) state <= WRITE_ACK;
                                        else counter <= counter - 1;
                                end
                                
                                WRITE_ACK: begin
                                        state <= STOP;
                                end

                                STOP: begin
                                        state <= IDLE;
                                end
                        endcase
                end
        end
        
        always @(negedge i2c_clk, posedge rst) begin
                if(rst == 1) begin
                        write_enable <= 1;
                        sda_out <= 1;
                end else begin
                        case(state)
                                
                                START: begin
                                        write_enable <= 1;
                                        sda_out <= 0;
                                end
                                
                                ADDRESS: begin
                                        sda_out <= saved_addr[counter];
                                end
                                
                                READ_ACK: begin
                                        write_enable <= 0;
                                end
                                
                                WRITE_DATA: begin 
                                        write_enable <= 1;
                                        sda_out <= saved_data[counter];
                                end
                                
                                WRITE_ACK: begin
                                        write_enable <= 1;
                                        sda_out <= 0;
                                end
                                
                                READ_DATA: begin
                                        write_enable <= 0;                                
                                end
                                
                                STOP: begin
                                        write_enable <= 1;
                                        sda_out <= 1;
                                end
                        endcase
                end
        end

endmodule

// SLAVE 

module i2c_slave_controller #(parameter ADDRESS = 7'b0101010)(
    inout wire sda,
    inout wire scl
);

        
        // localparam ADDRESS = 7'b0101010;
        
        localparam READ_ADDR = 0;
        localparam SEND_ACK = 1;
        localparam READ_DATA = 2;
        localparam WRITE_DATA = 3;
        localparam SEND_ACK2 = 4;
        
        reg [7:0] addr;
        reg [7:0] counter;
        reg [7:0] state = 0;
        reg [7:0] data_in = 0;
        reg [7:0] data_out = 8'b11001100;
        reg sda_out = 0;
        reg sda_in = 0;
        reg start = 0;
        reg write_enable = 0;
        
        assign sda = (write_enable == 1) ? sda_out : 'bz;
        
        always @(negedge sda) begin
                if ((start == 0) && (scl == 1)) begin
                        start <= 1;        
                        counter <= 7;
                end
        end
        
        always @(posedge sda) begin
                if ((start == 1) && (scl == 1)) begin
                        state <= READ_ADDR;
                        start <= 0;
                        write_enable <= 0;
                end
        end
        
        always @(posedge scl) begin
                if (start == 1) begin
                        case(state)
                                READ_ADDR: begin
                                        addr[counter] <= sda;
                                        if(counter == 0) state <= SEND_ACK;
                                        else counter <= counter - 1;                                        
                                end
                                
                                SEND_ACK: begin
                                        if(addr[7:1] == ADDRESS) begin
                                                counter <= 7;
                                                if(addr[0] == 0) begin 
                                                        state <= READ_DATA;
                                                end
                                                else state <= WRITE_DATA;
                                        end
                                end
                                
                                READ_DATA: begin
                                        data_in[counter] <= sda;
                                        if(counter == 0) begin
                                                state <= SEND_ACK2;
                                        end else counter <= counter - 1;
                                end
                                
                                SEND_ACK2: begin
                                        state <= READ_ADDR;                                        
                                end
                                
                                WRITE_DATA: begin
                                        if(counter == 0) state <= READ_ADDR;
                                        else counter <= counter - 1;                
                                end
                                
                        endcase
                end
        end
        
        always @(negedge scl) begin
                case(state)
                        
                        READ_ADDR: begin
                                write_enable <= 0;                        
                        end
                        
                        SEND_ACK: begin
                                sda_out <= 0;
                                write_enable <= 1;        
                        end
                        
                        READ_DATA: begin
                                write_enable <= 0;
                        end
                        
                        WRITE_DATA: begin
                                sda_out <= data_in[counter];
                                write_enable <= 1;
                        end
                        
                        SEND_ACK2: begin
                                sda_out <= 0;
                                write_enable <= 1;
                        end
                endcase
        end
endmodule
