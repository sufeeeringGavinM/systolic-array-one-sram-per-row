// Feeds activations into a row and writes results back
// PE Row N's dedicated SRAM writes results back from PE Column N.

`timescale 1ns / 1ps

module row_feeder #(
    parameter ROW_INDEX = 0,
    parameter BIT_WIDTH = 8,
    parameter ADDR_WIDTH = 8,
    parameter SKEW_WIDTH = 3,
    parameter WB_CNT_WIDTH = 8,
    parameter OUT_LATENCY = 5
) (
    input clk,
    input clear,
    input load_weights,

    input [  SKEW_WIDTH-1:0] skew_cnt,
    input [WB_CNT_WIDTH-1:0] writeback_cnt,

    // If SRAM is writing from off-chip DRAM, this row_feeder module handles who gets to write first instead of the SRAM array itself.
    input                  sram_we_ext,
    input [ADDR_WIDTH-1:0] sram_waddr_ext,
    input [ BIT_WIDTH-1:0] sram_wdata_ext,

    input [BIT_WIDTH-1:0] result_in,

    output [BIT_WIDTH-1:0] activation_out
);

  localparam WB_START_CYCLE = ROW_INDEX + OUT_LATENCY; // Row N starts writing back at N + (OUT_LATENCY) = N + (ARRAY_SIZE + 1)                                             

  wire streaming = !load_weights;
  wire row_active = (skew_cnt >= ROW_INDEX);
  wire feed_enable = streaming && row_active;          // When to start feeding input activations? When we aren't loading weights and when it's our row's time based on skew

  // Where and when in the SRAM array we're reading and about to read.                                
  // For now, simply sequential, in the actual channel-first im2col, it will be address generation.
  reg [ADDR_WIDTH-1:0] rd_ptr;
  wire [ADDR_WIDTH-1:0] rd_ptr_next = rd_ptr + 1'b1;
  wire [ADDR_WIDTH-1:0] rd_addr = feed_enable ? rd_ptr_next : 0; // SRAM has one-cycle read latency which is why rd_addr=next addr actually
  wire [BIT_WIDTH-1:0] sram_rdata;

  // Read when it's time to read.
  always @(posedge clk) begin
    if (clear) rd_ptr <= {ADDR_WIDTH{1'b0}};
    else if (row_active) rd_ptr <= rd_ptr_next;
  end

  // Feed when it's time to feed.
  assign activation_out = feed_enable ? sram_rdata : {BIT_WIDTH{1'b0}};

  // Where and when in the SRAM array we're writing
  reg [ADDR_WIDTH-1:0] wb_ptr;
  wire wb_valid = streaming && (writeback_cnt >= WB_START_CYCLE);

  // Write when it's time to write
  always @(posedge clk) begin
    if (clear) wb_ptr <= {ADDR_WIDTH{1'b0}};
    else if (wb_valid) wb_ptr <= wb_ptr + 1'b1;
  end
  
  wire                  sram_we = sram_we_ext | wb_valid;

  // Write from external takes priority in case of conflict
  wire [ADDR_WIDTH-1:0] sram_waddr = sram_we_ext ? sram_waddr_ext : wb_ptr;
  wire [ BIT_WIDTH-1:0] sram_wdata = sram_we_ext ? sram_wdata_ext : result_in;

  row_sram #(
      .BIT_WIDTH (BIT_WIDTH),
      .ADDR_WIDTH(ADDR_WIDTH)
  ) u_sram (
      .clk  (clk),
      .we   (sram_we),
      .waddr(sram_waddr),
      .wdata(sram_wdata),
      .raddr(rd_addr),
      .rdata(sram_rdata)
  );

endmodule
