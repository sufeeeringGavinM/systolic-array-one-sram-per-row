// The systolic array with internal skewing and writeback logic

`timescale 1ns / 1ps

module MMU #(
    parameter ARRAY_SIZE = 4,
    parameter BIT_WIDTH  = 8,
    parameter ACC_WIDTH  = 32,
    parameter ADDR_WIDTH = 8
) (
    input clk,
    input nrst,
    input load_weights,

    input [ARRAY_SIZE-1:0]                 sram_we_ext,
    input [ARRAY_SIZE-1:0][ADDR_WIDTH-1:0] sram_waddr_ext,
    input [ARRAY_SIZE-1:0][ BIT_WIDTH-1:0] sram_wdata_ext,

    input [ARRAY_SIZE-1:0][BIT_WIDTH-1:0] weight_row_in,

    output reg [ARRAY_SIZE-1:0][ACC_WIDTH-1:0] acc_col_out
);

  localparam OUT_LATENCY = ARRAY_SIZE + 1;                    // How long will the last column take to come out? #Pride                        
  localparam SKEW_WIDTH = $clog2(ARRAY_SIZE + 2);             // How long must the last row be delayed?                                        
  localparam WB_CNT_WIDTH = $clog2(OUT_LATENCY + ARRAY_SIZE + (1<<ADDR_WIDTH)); // How wide must the WB counter be to reach the last row's first writeback cycle?

  wire clear = !nrst || load_weights;  // When to reset skew and writeback count?

  wire [ARRAY_SIZE-1:0][ARRAY_SIZE-1:0][BIT_WIDTH-1:0] mac_data_in, mac_data_out;     // Buses between columns
  wire [ARRAY_SIZE-1:0][ARRAY_SIZE-1:0][BIT_WIDTH-1:0] mac_weight_in, mac_weight_out; // Buses between rows   
  wire [ARRAY_SIZE-1:0][ARRAY_SIZE-1:0][ACC_WIDTH-1:0] mac_acc_in, mac_acc_out;       // Buses between rows   

  reg [SKEW_WIDTH-1:0] skew_cnt;
  always @(posedge clk) begin
    if (clear) skew_cnt <= 0;
    else if (skew_cnt <= ARRAY_SIZE) skew_cnt <= skew_cnt + 1'b1;
  end

  reg [WB_CNT_WIDTH-1:0] writeback_cnt;
  always @(posedge clk) begin
    if (clear) writeback_cnt <= 0;
    else writeback_cnt <= writeback_cnt + 1'b1;
  end

  genvar row, col;
  generate
    for (row = 0; row < ARRAY_SIZE; row = row + 1) begin : g_row

      wire [BIT_WIDTH-1:0] col_result;  // Results per column fed to each SRAM row. Truncated for now, deserializer manages this in actual channel-first im2col.
      wire [BIT_WIDTH-1:0] row_activation;        // Inputs from SRAM fed per PE row

      assign col_result = acc_col_out[row][BIT_WIDTH-1:0]; // Column N to PE row N

      row_feeder #(
          .ROW_INDEX(row),
          .BIT_WIDTH(BIT_WIDTH),
          .ADDR_WIDTH(ADDR_WIDTH),
          .SKEW_WIDTH(SKEW_WIDTH),
          .WB_CNT_WIDTH(WB_CNT_WIDTH),
          .OUT_LATENCY(OUT_LATENCY)
      ) u_feeder (
          .clk           (clk),
          .clear         (clear),
          .load_weights  (load_weights),
          .skew_cnt      (skew_cnt),
          .writeback_cnt (writeback_cnt),
          .sram_we_ext   (sram_we_ext[row]),
          .sram_waddr_ext(sram_waddr_ext[row]),
          .sram_wdata_ext(sram_wdata_ext[row]),
          .result_in     (col_result),
          .activation_out(row_activation)
      );

      for (col = 0; col < ARRAY_SIZE; col = col + 1) begin : g_col

        // Leftmost column of PEs takes from SRAM arrays, otherwise from PE from the left
        if (col == 0) begin
          assign mac_data_in[row][col] = row_activation;
        end else begin
          assign mac_data_in[row][col] = mac_data_out[row][col-1];
        end

        // Topmost acc row accumulates nothing, otherwise from PE from the top
        // Weights load if load_weights, otherwise nothing.
        if (row == 0) begin
          assign mac_acc_in[row][col]    = 0;
          assign mac_weight_in[row][col] = load_weights ? weight_row_in[col] : 0;
        end else begin
          assign mac_acc_in[row][col]    = mac_acc_out[row-1][col];
          assign mac_weight_in[row][col] = load_weights ? mac_weight_out[row-1][col] : 0;
        end

        MAC #(
            .BIT_WIDTH(BIT_WIDTH),
            .ACC_WIDTH(ACC_WIDTH)
        ) u_MAC (
            .nrst        (nrst),
            .clk         (clk),
            .load_weights(load_weights),
            .data_in     (mac_data_in[row][col]),
            .weight_in   (mac_weight_in[row][col]),
            .acc_in      (mac_acc_in[row][col]),
            .data_out    (mac_data_out[row][col]),
            .weight_out  (mac_weight_out[row][col]),
            .acc_out     (mac_acc_out[row][col])
        );

      end
    end
  endgenerate

  always @(posedge clk) begin
    if (!nrst) acc_col_out <= 0;
    else acc_col_out <= mac_acc_out[ARRAY_SIZE-1];
  end

endmodule
