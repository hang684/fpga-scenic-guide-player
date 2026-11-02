`timescale 1ns/1ps
module audio_fft16_spectrum (
 input wire clk,input wire rst_n,input wire sample_valid,input wire signed [15:0] sample_in,
 output reg frame_valid,output reg [15:0] magnitude0,output reg [15:0] magnitude1,
 output reg [15:0] magnitude2,output reg [15:0] magnitude3,output reg [15:0] magnitude4,
 output reg [15:0] magnitude5,output reg [15:0] magnitude6,output reg [15:0] magnitude7);
 reg signed [15:0] mem[0:7]; reg [2:0] wr,bin,si; reg busy;
 reg signed [31:0] rr,ii; reg signed [31:0] tr,ti; reg signed [31:0] mag;
 integer i;
 always @* begin
   case ((bin*si)&3'd7)
    0: begin tr=mem[si];ti=0; end 1: begin tr=mem[si]>>>1;ti=-(mem[si]>>>1); end
    2: begin tr=0;ti=-mem[si]; end 3: begin tr=-(mem[si]>>>1);ti=-(mem[si]>>>1); end
    4: begin tr=-mem[si];ti=0; end 5: begin tr=-(mem[si]>>>1);ti=mem[si]>>>1; end
    6: begin tr=0;ti=mem[si]; end default: begin tr=mem[si]>>>1;ti=mem[si]>>>1; end
   endcase
   mag=(rr[31]?-rr:rr)+(ii[31]?-ii:ii);
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin wr<=0;bin<=0;si<=0;busy<=0;frame_valid<=0;rr<=0;ii<=0;
   magnitude0<=0;magnitude1<=0;magnitude2<=0;magnitude3<=0;magnitude4<=0;magnitude5<=0;magnitude6<=0;magnitude7<=0;
   for(i=0;i<8;i=i+1) mem[i]<=0;
  end else begin
   frame_valid<=0;
   if(!busy) begin if(sample_valid) begin mem[wr]<=sample_in; if(wr==7) begin wr<=0;bin<=0;si<=0;rr<=0;ii<=0;busy<=1; end else wr<=wr+1; end end
   else begin rr<=rr+tr;ii<=ii+ti; if(si==7) begin
    case(bin) 0:magnitude0<=mag[15:0];1:magnitude1<=mag[15:0];2:magnitude2<=mag[15:0];3:magnitude3<=mag[15:0];4:magnitude4<=mag[15:0];5:magnitude5<=mag[15:0];6:magnitude6<=mag[15:0];default:magnitude7<=mag[15:0]; endcase
    rr<=0;ii<=0;si<=0; if(bin==7) begin busy<=0;frame_valid<=1;end else bin<=bin+1; end else si<=si+1;
   end
  end
 end
endmodule
