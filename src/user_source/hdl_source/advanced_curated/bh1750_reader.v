`timescale 1ns/1ps
module bh1750_reader #(parameter integer CLK_HZ=100_000_000, parameter [15:0] NIGHT_THRESHOLD=16'd40)(
 input wire clk,input wire rst_n,output reg scl_oe,output reg sda_oe,input wire sda_in,
 output reg [15:0] lux_raw,output reg lux_valid,output reg night_mode,
 output reg [3:0] debug_code, output reg [7:0] debug_samples);
 localparam integer DIV=(CLK_HZ/200_000), MEAS=(CLK_HZ/8);
 localparam [5:0] IDLE=0,START0=1,START1=2,START2=3,TX0=4,TX1=5,ACK0=6,ACK1=7,ACK2=8,STOP0=9,STOP1=10,STOP2=11,WAIT=12,
                  RSTART0=13,RSTART1=14,RSTART2=15,RX0=16,RX1=17,RX2=18,MA0=19,MA1=20,MN0=21,MN1=22,RSTOP0=23,RSTOP1=24,RSTOP2=25,TX2=26;
 reg [5:0] st; reg [15:0] dc; reg [31:0] wc; reg [7:0] tx; reg [3:0] bit; reg [15:0] rx; reg byte_sel;
 wire tick=(dc==DIV-1);
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin st<=IDLE;dc<=0;wc<=0;scl_oe<=0;sda_oe<=0;tx<=0;bit<=0;rx<=0;byte_sel<=0;lux_raw<=0;lux_valid<=0;night_mode<=0;debug_code<=0;debug_samples<=0; end
  else begin lux_valid<=0; if(!tick) dc<=dc+1'b1; else begin dc<=0; case(st)
   IDLE: begin tx<=8'h46;bit<=0;st<=START0;end
   START0: begin scl_oe<=0;sda_oe<=0;st<=START1;end
   START1: begin scl_oe<=0;sda_oe<=1;st<=START2;end
   START2: begin scl_oe<=1;sda_oe<=1;st<=TX0;end
   TX0: begin scl_oe<=1;sda_oe<=~tx[7-bit];st<=TX1;end
   TX1: begin scl_oe<=0;st<=TX2;end
   TX2: begin scl_oe<=1;if(bit==7) begin bit<=0;st<=ACK0;end else begin bit<=bit+1'b1;st<=TX0;end end
   ACK0: begin sda_oe<=0;scl_oe<=0;st<=ACK1;end
   ACK1: begin scl_oe<=1;st<=ACK2;end
   ACK2: begin scl_oe<=1;if(sda_in) begin debug_code<=(tx==8'h46)?4'h1:(tx==8'h01)?4'h2:(tx==8'h10)?4'h3:4'h4;tx<=0;st<=STOP0;end else if(tx==8'h46) begin debug_code<=4'h5;tx<=8'h01;st<=TX0;end else if(tx==8'h01) begin debug_code<=4'h6;tx<=8'h10;st<=TX0;end else if(tx==8'h10) begin debug_code<=4'h7;st<=STOP0;end else begin debug_code<=4'h8;bit<=0;byte_sel<=0;rx<=0;st<=RX0;end end
   STOP0: begin sda_oe<=1;scl_oe<=0;st<=STOP1;end
   STOP1: begin sda_oe<=1;scl_oe<=1;st<=STOP2;end
   STOP2: begin sda_oe<=0;scl_oe<=0;if(tx==8'h10) begin wc<=0;st<=WAIT;end else st<=IDLE;end
   WAIT: begin if(wc==MEAS-1) begin tx<=8'h47;st<=RSTART0;end else wc<=wc+1'b1;end
   RSTART0: begin scl_oe<=0;sda_oe<=0;st<=RSTART1;end
   RSTART1: begin scl_oe<=0;sda_oe<=1;st<=RSTART2;end
   RSTART2: begin scl_oe<=1;sda_oe<=1;st<=TX0;end
   RX0: begin sda_oe<=0;scl_oe<=0;st<=RX1;end
   RX1: begin scl_oe<=1;st<=RX2;end
   RX2: begin rx<={rx[14:0],sda_in};scl_oe<=0;if(bit==7) begin bit<=0;if(byte_sel==0) st<=MA0;else st<=MN0;end else begin bit<=bit+1'b1;st<=RX0;end end
   MA0: begin sda_oe<=1;scl_oe<=0;st<=MA1;end
   MA1: begin scl_oe<=1;byte_sel<=1;st<=RX0;end
   MN0: begin sda_oe<=0;scl_oe<=0;st<=MN1;end
   MN1: begin scl_oe<=1;st<=RSTOP0;end
   RSTOP0: begin sda_oe<=1;scl_oe<=0;st<=RSTOP1;end
   RSTOP1: begin sda_oe<=1;scl_oe<=1;st<=RSTOP2;end
   RSTOP2: begin sda_oe<=0;scl_oe<=0;lux_raw<=rx;lux_valid<=1;night_mode<=(rx<NIGHT_THRESHOLD);debug_code<=4'h9;debug_samples<=debug_samples+1'b1;st<=IDLE;end
   default: st<=IDLE;
  endcase end end
 end
endmodule
