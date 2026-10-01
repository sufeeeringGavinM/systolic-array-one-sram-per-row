`timescale 1ns / 1ps

module tb_MMU;

  localparam ARRAY_SIZE = 5;  // ARRAY_SIZE x ARRAY_SIZE square systolic array.
  localparam INPUT_ROWS = 5;  // Rows per input matrix (elements fed per PE row per matrix).
  localparam NUM_MATRICES = 2;  // Input matrices streamed back-to-back against ONE weight load.
  localparam TOTAL_ROWS = INPUT_ROWS * NUM_MATRICES;  // SRAM addresses used per PE row.
  localparam BIT_WIDTH = 32;  // 32 for now to see SRAM's written outputs properly.
  localparam ACC_WIDTH = 32;
  localparam ADDR_WIDTH = 8;

  // Original single-matrix run was 3*ARRAY_SIZE + 1.
  // Each extra input row adds one more cycle before the last writeback lands.
  localparam RUN_CYCLES = 3 * ARRAY_SIZE + 1 + (TOTAL_ROWS - INPUT_ROWS);

  localparam WEIGHT_FILE = "sim/weight_matrix.txt";
  localparam INPUT_FILE_A = "sim/input_matrix.txt";
  localparam INPUT_FILE_B = "sim/input_matrix_b.txt";
  localparam SRAM_OUT_FILE = "sim/output_matrix_sram_2mat.txt";

  reg clk;
  reg nrst;
  reg load_weights;
  reg [ARRAY_SIZE-1:0] sram_we_ext;
  reg [ARRAY_SIZE-1:0][ADDR_WIDTH-1:0] sram_waddr_ext;
  reg [ARRAY_SIZE-1:0][BIT_WIDTH-1:0] sram_wdata_ext;
  reg [ARRAY_SIZE-1:0][BIT_WIDTH-1:0] weight_row_in;

  wire [ARRAY_SIZE-1:0][ACC_WIDTH-1:0] acc_col_out;

  reg [BIT_WIDTH-1:0] weight_matrix[0:ARRAY_SIZE*ARRAY_SIZE-1];
  // Matrix A occupies rows 0..INPUT_ROWS-1, matrix B occupies rows INPUT_ROWS..TOTAL_ROWS-1.
  reg [BIT_WIDTH-1:0] input_matrix[0:TOTAL_ROWS*ARRAY_SIZE-1];

  reg [63:0] cycle_counter;  // Solely for output in terminal thingy

  integer addr, row, col;
  integer fd;

`ifdef USE_POWER_PINS
  wire VDD = 1'b1;
  wire VSS = 1'b0;
`endif

  MMU #(
      .ARRAY_SIZE(ARRAY_SIZE),
      .BIT_WIDTH (BIT_WIDTH),
      .ACC_WIDTH (ACC_WIDTH),
      .ADDR_WIDTH(ADDR_WIDTH)
  ) UUT (
`ifdef USE_POWER_PINS
      .VPWR          (VDD),
      .VGND          (VSS),
`endif
      .clk           (clk),
      .nrst          (nrst),
      .load_weights  (load_weights),
      .sram_we_ext   (sram_we_ext),
      .sram_waddr_ext(sram_waddr_ext),
      .sram_wdata_ext(sram_wdata_ext),
      .weight_row_in (weight_row_in),
      .acc_col_out   (acc_col_out)
  );

  always #250 clk = !clk;

`ifdef ENABLE_SDF
  initial begin
    $sdf_annotate("final/MMU__nom_tt_025C_1v80.sdf", UUT);
  end
`endif

  // Preloading SRAM arrays with both input matrices, back-to-back.
  // SRAM row r, address a  =  input_matrix[a][r]   (a = 0..TOTAL_ROWS-1)
  task load_input_matrix_to_srams;
    begin
      for (addr = 0; addr < TOTAL_ROWS; addr = addr + 1) begin
        for (row = 0; row < ARRAY_SIZE; row = row + 1) begin
          sram_waddr_ext[row] <= addr;
          sram_wdata_ext[row] <= input_matrix[addr*ARRAY_SIZE+row];
        end
        sram_we_ext <= {ARRAY_SIZE{1'b1}};
        @(posedge clk);
      end
      sram_we_ext <= 0;
    end
  endtask

  // Loading in stationary weights
  task load_weight_matrix;
    begin
      for (row = ARRAY_SIZE - 1; row >= 0; row = row - 1) begin
        for (col = 0; col < ARRAY_SIZE; col = col + 1) begin
          weight_row_in[col] <= weight_matrix[row*ARRAY_SIZE+col];
        end
        @(posedge clk);
      end
    end
  endtask

  // For dumping all sram contents into a separate file.

  wire [BIT_WIDTH-1:0] sram_dump[0:ARRAY_SIZE-1][0:TOTAL_ROWS-1];
  genvar dump_row, dump_addr;
  generate
    for (dump_row = 0; dump_row < ARRAY_SIZE; dump_row = dump_row + 1) begin : g_dump_row
      for (dump_addr = 0; dump_addr < TOTAL_ROWS; dump_addr = dump_addr + 1) begin : g_dump_addr
        assign sram_dump[dump_row][dump_addr] = UUT.g_row[dump_row].u_feeder.u_sram.mem[dump_addr];
      end
    end
  endgenerate

  task dump_sram;
    begin
      fd = $fopen(SRAM_OUT_FILE, "w");
      for (row = 0; row < ARRAY_SIZE; row = row + 1) begin
        $fdisplay(fd, "PE row %0d SRAM:", row);
        for (addr = 0; addr < TOTAL_ROWS; addr = addr + 1) begin
          $fdisplay(fd, "  addr %0d = %08h%s", addr, sram_dump[row][addr],
                    (addr % INPUT_ROWS == 0) ? "   <- matrix start" : "");
        end
      end
      $fclose(fd);
    end
  endtask

  initial begin
    $dumpfile("tb_MMU.vcd");
    $dumpvars(0, tb_MMU);

    $readmemh(WEIGHT_FILE, weight_matrix);
    $readmemh(INPUT_FILE_A, input_matrix, 0);  // Matrix A
    $readmemh(INPUT_FILE_B, input_matrix, INPUT_ROWS * ARRAY_SIZE);  // Matrix B right after

    cycle_counter = 0;
    clk = 0;
    load_weights = 1;
    sram_we_ext = 0;
    sram_waddr_ext = 0;
    sram_wdata_ext = 0;
    weight_row_in = 0;
    nrst = 0;

    @(posedge clk);

    nrst <= 1;

    @(posedge clk);

    load_input_matrix_to_srams;
    load_weight_matrix;

    load_weights <= 0;
    repeat (RUN_CYCLES) @(posedge clk);

    dump_sram;

    $finish(1);
  end

  integer out_col;
  always @(posedge clk) begin
    #10;
    cycle_counter <= cycle_counter + 1;

    $write("[OUTPUT] time=%0d", cycle_counter);
    for (out_col = ARRAY_SIZE - 1; out_col >= 0; out_col = out_col - 1)
    $write(" y%0d=%0d", out_col, acc_col_out[out_col]);
    $display("");
  end

endmodule