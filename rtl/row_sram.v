// Simulated SRAM with one read and one write port.
// That is different from the paper! They use 1 R/W port.

// They get away with that because they can time-multiplex read and write every 8 cycles due to their word size being 8 elements. One read/write, 8 elements at once through a serializer and deserializer.
// For the sake of this implementation, we split the read and write ports since we don't have a serializer and deserializer yet.

`timescale 1ns / 1ps

module row_sram #(
    parameter BIT_WIDTH  = 8,
    parameter ADDR_WIDTH = 8
) (
    input                  clk,
    input                  we,
    input [ADDR_WIDTH-1:0] waddr,
    input [ BIT_WIDTH-1:0] wdata,
    input [ADDR_WIDTH-1:0] raddr,

    output reg [BIT_WIDTH-1:0] rdata
);
  localparam DEPTH = 1 << ADDR_WIDTH;

  reg [BIT_WIDTH-1:0] mem[0:DEPTH-1];

  always @(posedge clk) begin
    if (we) mem[waddr] <= wdata;
    rdata <= mem[raddr];
  end

endmodule
