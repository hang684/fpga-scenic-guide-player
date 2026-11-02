`timescale 1ns/1ps
// Packs PCM samples into 512-byte sectors. The SD interface requests the
// next byte one cycle before consuming it (same convention as config writer).
// LBA traversal and read-back verification are supplied by the file controller.
module record_sector_packer #(
 parameter integer MAX_SAMPLES=1440000
)(
 input wire clk,input wire rst_n,input wire start,input wire stop,
 input wire sample_valid,input wire [15:0] sample,
 input wire writer_ready,input wire byte_request,input wire sector_done,
 output wire [7:0] byte_data,output reg sector_request,
 output reg active,output reg drained,output reg failed,
 output wire [31:0] samples_captured,
 output wire [31:0] sectors_written
);
 localparam CW=$clog2(MAX_SAMPLES+1);
 localparam SW=$clog2((MAX_SAMPLES+255)/256+1);
 reg [CW-1:0] captured;
 reg [SW-1:0] written;
 assign samples_captured=captured;
 assign sectors_written=written;
 wire [15:0] head;
 wire [11:0] level;
 wire overflow;
 reg stopping,busy;
 reg [8:0] byte_index;
 reg [15:0] held_sample;
 wire accept=active && !stopping && !stop && sample_valid && captured<MAX_SAMPLES;
 wire consume=busy && byte_request && !byte_index[0] && level!=0;
 record_pcm_fifo fifo(.clk(clk),.rst_n(rst_n),.clear(start && !active),
  .push(accept),.sample(sample),.pop(consume),.head(head),.level(level),.overflow(overflow));
 assign byte_data=byte_index[0]?held_sample[15:8]:held_sample[7:0];
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   active<=0;drained<=0;failed<=0;stopping<=0;busy<=0;
   byte_index<=9'h1ff;held_sample<=0;sector_request<=0;
   captured<=0;written<=0;
  end else begin
   sector_request<=0;
   if(start && !active) begin
    active<=1;drained<=0;failed<=0;stopping<=0;busy<=0;
    captured<=0;written<=0;byte_index<=9'h1ff;
   end else if(active) begin
    if(accept) captured<=captured+1'b1;
    if(stop || captured==MAX_SAMPLES || overflow) stopping<=1;
    if(overflow) failed<=1;
    if(!busy && writer_ready && (level>=256 || (stopping && level!=0))) begin
     busy<=1;sector_request<=1;byte_index<=9'h1ff;
    end
    if(busy && byte_request) begin
     byte_index<=byte_index+1'b1;
     // Old index 511/odd means the requested next byte is a low byte.
     if(byte_index[0]) held_sample<=level!=0?head:16'd0;
    end
    if(busy && sector_done) begin busy<=0;written<=written+1'b1;end
    if(stopping && !busy && level==0) begin active<=0;drained<=1;end
   end
  end
 end
endmodule
