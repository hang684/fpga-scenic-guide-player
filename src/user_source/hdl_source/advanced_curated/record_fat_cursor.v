`timescale 1ns/1ps
// Read-only FAT32 cursor for a preallocated file. Never changes FAT/directory.
// open publishes the header LBA; advance publishes each following sector.
// The owner must serialize these FAT reads with all other SD requests.
module record_fat_cursor #(
 parameter integer TIMEOUT_CYCLES=100000000,parameter integer MAX_FILE_BYTES=2880512
)(
 input wire clk,rst_n,open,advance,cancel,
 input wire [31:0] first_cluster,file_bytes,fat_start_lba,data_start_lba,max_cluster,
 input wire [7:0] sectors_per_cluster,
 output wire busy,output wire lba_valid,
 output reg [31:0] lba,output wire [31:0] sector_number,
 output reg failed,output reg [7:0] error,
 output reg sector_req,output reg [31:0] sector_lba,
 input wire sector_busy,sector_valid,
 input wire [8:0] sector_byte_index,input wire [7:0] sector_byte,
 input wire sector_done,input wire [7:0] sector_error
);
 localparam IDLE=0,ADDR=1,VALID=2,FAT_REQ=3,FAT_WAIT=4,FAT_CHECK=5,STOP=6;
 reg [2:0] state;
 localparam NW=$clog2(MAX_FILE_BYTES/512+1);
 localparam TW=$clog2(TIMEOUT_CYCLES+1);
 reg [27:0] cluster,next_cluster,cluster_delta;
 reg [NW-1:0] limit,sector_index;
 reg [TW-1:0] watchdog;
 assign sector_number=sector_index;
 reg [31:0] fat_base,data_base;reg [27:0] last_cluster;
 reg [7:0] spc,in_cluster;
 reg [2:0] shift;
 reg [3:0] fat_seen;
 reg cancel_pending;
 wire [8:0] fat_offset={cluster[6:0],2'b00};
 assign busy=state==ADDR || state==FAT_REQ || state==FAT_WAIT || state==FAT_CHECK;
 assign lba_valid=state==VALID && !failed;
 function [2:0] log_spc;
 input [7:0] n;
 begin case(n)
  2:log_spc=1;4:log_spc=2;8:log_spc=3;16:log_spc=4;
  32:log_spc=5;64:log_spc=6;128:log_spc=7;default:log_spc=0;
 endcase end
 endfunction
 reg rx_valid,rx_done,rx_match;
 reg [1:0] rx_index;
 reg [7:0] rx_byte,rx_error;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin rx_valid<=0;rx_done<=0;rx_match<=0;rx_index<=0;rx_byte<=0;rx_error<=0;end
  else begin
   rx_valid<=sector_valid;rx_done<=sector_done;rx_error<=sector_error;
   rx_match<=sector_byte_index[8:2]==cluster[6:0];
   rx_index<=sector_byte_index[1:0];rx_byte<=sector_byte;
  end
 end
 task fail;
 input [7:0] code;
 begin failed<=1;error<=code;state<=STOP;end
 endtask
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=IDLE;cluster<=0;next_cluster<=0;limit<=0;watchdog<=0;
   cluster_delta<=0;fat_base<=0;data_base<=0;last_cluster<=0;
   spc<=0;in_cluster<=0;shift<=0;fat_seen<=0;cancel_pending<=0;
   lba<=0;sector_index<=0;failed<=0;error<=0;sector_req<=0;sector_lba<=0;
  end else begin
   sector_req<=0;
   if(cancel) cancel_pending<=1;
   // Cancellation waits for an outstanding read to finish. The owner must
   // retain bus ownership until busy falls; late bytes cannot reach a new job.
   if((cancel || cancel_pending) && state!=FAT_WAIT) begin
    state<=IDLE;cancel_pending<=0;
   end
   else if(open && (state==IDLE || state==STOP || state==VALID)) begin
    failed<=0;error<=0;sector_index<=0;in_cluster<=0;
    cluster<=first_cluster;cluster_delta<=first_cluster-2;
    fat_base<=fat_start_lba;data_base<=data_start_lba;last_cluster<=max_cluster;
    spc<=sectors_per_cluster;shift<=log_spc(sectors_per_cluster);
    limit<=file_bytes>>9;
    if(first_cluster<2 || first_cluster>max_cluster || file_bytes<512 || file_bytes>MAX_FILE_BYTES || first_cluster[31:28]!=0 ||
       file_bytes[8:0]!=0 || sectors_per_cluster==0 ||
       (sectors_per_cluster & (sectors_per_cluster-1'b1))!=0)
     fail(8'h01);
    else state<=ADDR;
   end else case(state)
    ADDR: begin lba<=data_base+(cluster_delta<<shift);state<=VALID;end
    VALID: if(advance) begin
     if(sector_index+1>=limit) fail(8'h02);
     else begin
      sector_index<=sector_index+1'b1;
      if(in_cluster+1<spc) begin in_cluster<=in_cluster+1'b1;lba<=lba+1'b1;end
      else begin in_cluster<=0;watchdog<=0;state<=FAT_REQ;end
     end
    end
    FAT_REQ: begin
     if(!sector_busy) begin
      sector_lba<=fat_base+(cluster>>7);sector_req<=1;
      next_cluster<=0;fat_seen<=0;watchdog<=0;state<=FAT_WAIT;
     end else if(watchdog>=TIMEOUT_CYCLES-1) fail(8'h03);
     else watchdog<=watchdog+1'b1;
    end
    FAT_WAIT: begin
     if(rx_valid && rx_match) begin
      case(rx_index)
       0:next_cluster[7:0]<=rx_byte;
       1:next_cluster[15:8]<=rx_byte;
       2:next_cluster[23:16]<=rx_byte;
       3:next_cluster[27:24]<=rx_byte[3:0];
      endcase
      fat_seen[rx_index]<=1;
     end
     if(rx_error!=0) fail(8'h04);
     else if(rx_done) begin
      if(cancel || cancel_pending) begin state<=IDLE;cancel_pending<=0;end
      else state<=FAT_CHECK;
     end else if(watchdog>=TIMEOUT_CYCLES-1) fail(8'h03);
     else watchdog<=watchdog+1'b1;
    end
    FAT_CHECK: begin
     // A truncated, reserved, bad, or self-linked chain must never be written.
     if(fat_seen!=4'hf || next_cluster<2 || next_cluster>last_cluster ||
        next_cluster>=32'h0ffffff0 || next_cluster==cluster) fail(8'h05);
     else begin cluster<=next_cluster;cluster_delta<=next_cluster-2;state<=ADDR;end
    end
    default:;
   endcase
  end
 end
endmodule
