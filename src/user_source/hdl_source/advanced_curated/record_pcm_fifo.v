`timescale 1ns/1ps
// Single-clock PCM16 FIFO for the SD writer. Pop one complete sample after
// transmitting its high byte. Overflow is sticky: never commit such a take.
module record_pcm_fifo #(parameter AW=11)(
 input wire clk, input wire rst_n, input wire clear,
 input wire push, input wire [15:0] sample,
 input wire pop, output wire [15:0] head,
 output reg [AW:0] level, output reg overflow
);
 localparam DEPTH=1<<AW;
 reg [15:0] mem[0:DEPTH-1]; /* fehdl force_ram=1, ram_style="bram" */
 reg [AW-1:0] wr,rd;
 wire take=pop && level!=0;
 wire put=push && (level!=DEPTH || take);
 wire [AW-1:0] read_address=take ? rd+1'b1 : rd;
 reg [15:0] ram_head,forward_sample;
 reg forwarding;
 assign head=forwarding?forward_sample:ram_head;
 always @(posedge clk) begin
  if(put) mem[wr]<=sample;
  // Synchronous RAM read, with forwarding for read/write collisions.
  // The prefetched next head is visible immediately after a successful pop.
  ram_head<=mem[read_address];
  forwarding<=put && (level==0 || (take && level==1));
  if(put) forward_sample<=sample;
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin wr<=0;rd<=0;level<=0;overflow<=0;end
  else if(clear) begin wr<=0;rd<=0;level<=0;overflow<=0;end
  else begin
   if(put) wr<=wr+1'b1;
   if(take) rd<=rd+1'b1;
   case({put,take})
    2'b10:level<=level+1'b1;
    2'b01:level<=level-1'b1;
    default:;
   endcase
   if(push && !put) overflow<=1;
  end
 end
endmodule
