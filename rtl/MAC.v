// Processing element/MAC unit with stationary weight

`timescale 1ns / 1ps

module MAC #(                                                                 
    parameter BIT_WIDTH = 8,                                                  
    parameter ACC_WIDTH = 32                                                  
) (                                      
    input clk,                           
    input nrst,                          
    input load_weights,                   // control signal used to indicate if it is weight loading or not

    input [ACC_WIDTH-1:0] acc_in,         // accumulation in (a)
    input [BIT_WIDTH-1:0] data_in,        // data input or activation in (b)
    input [BIT_WIDTH-1:0] weight_in,      // weight data in (c)

    output reg [ACC_WIDTH-1:0] acc_out,   // accumulation out (a+b*c)
    output reg [BIT_WIDTH-1:0] data_out,  // activation out
    output reg [BIT_WIDTH-1:0] weight_out // weight data out
);                                                                            

  // The stationary weight
  // One for now, in actuality, we'll probably be double-buffering.
  reg  [BIT_WIDTH-1:0] stored_weight;
  wire [ACC_WIDTH-1:0] product = load_weights ? 'h0 : data_in * stored_weight;

  always @(posedge clk) begin                                                 
    if (!nrst) begin                                                          
      acc_out    <= 0;                                                        
      data_out   <= 0;                                                        
      weight_out <= 0;                                                        
    end else if (load_weights) begin                                          
      data_out      <= 'h0;                                                   
      acc_out       <= 'h0;                                                   
      stored_weight <= weight_in;                                             
      weight_out    <= weight_in;                                             
    end else begin                                                            
      data_out <= data_in;                                                    
      acc_out  <= acc_in + product;                                           
    end                                                                       
  end                                                                         

endmodule                                                                     
