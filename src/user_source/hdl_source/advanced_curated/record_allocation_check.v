`timescale 1ns/1ps
// Walk every FAT entry, including EOF, before permitting writes. Requiring EOF
// at exactly the allocated length rejects cycles without a large visited RAM.
module record_allocation_check #(parameter integer TIMEOUT_CYCLES=100000000,parameter integer MAX_FILE_BYTES=2880512)(
 input wire clk,rst_n,start,
 input wire [31:0] first_cluster,file_bytes,fat_start_lba,max_cluster,
 input wire [7:0] sectors_per_cluster,
 output wire busy,output reg done,valid,output reg [7:0] error,
 output reg sector_req,output reg [31:0] sector_lba,
 input wire sector_busy,sector_valid,input wire [8:0] sector_index,
 input wire [7:0] sector_byte,input wire sector_done,input wire [7:0] sector_error
);
 localparam IDLE=0,INIT=1,REQ=2,WAIT=3,CHECK=4,RESULT=5;
 reg [2:0] state,shift;
 localparam NW=$clog2(MAX_FILE_BYTES/512+1);
 localparam TW=$clog2(TIMEOUT_CYCLES+1);
 reg [27:0] cluster,next_cluster,last;
 reg [NW-1:0] needed,count;
 reg [TW-1:0] watchdog;
 reg [31:0] base;
 reg [3:0] seen;
 assign busy=state!=IDLE;
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
   rx_match<=sector_index[8:2]==cluster[6:0];
   rx_index<=sector_index[1:0];rx_byte<=sector_byte;
  end
 end
 task fail;
 input [7:0] code;
 begin error<=code;valid<=0;state<=RESULT;end
 endtask
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=IDLE;shift<=0;cluster<=0;next_cluster<=0;needed<=0;count<=0;watchdog<=0;
   base<=0;last<=0;seen<=0;done<=0;valid<=0;error<=0;sector_req<=0;sector_lba<=0;
  end else begin
   done<=0;sector_req<=0;
   case(state)
    IDLE: if(start) begin
     valid<=0;error<=0;cluster<=first_cluster;base<=fat_start_lba;last<=max_cluster;
     needed<=(file_bytes>>9)-1'b1;shift<=log_spc(sectors_per_cluster);count<=1;
     if(first_cluster<2 || first_cluster>max_cluster || file_bytes<512 || file_bytes>MAX_FILE_BYTES || first_cluster[31:28]!=0 || file_bytes[8:0]!=0 ||
        sectors_per_cluster==0 || (sectors_per_cluster & (sectors_per_cluster-1'b1))!=0)
      fail(8'h40);
     else state<=INIT;
    end
    INIT: begin needed<=(needed>>shift)+1'b1;watchdog<=0;state<=REQ;end
    REQ: begin
     if(!sector_busy) begin
      sector_lba<=base+(cluster>>7);sector_req<=1;
      seen<=0;next_cluster<=0;watchdog<=0;state<=WAIT;
     end else if(watchdog>=TIMEOUT_CYCLES-1) fail(8'h41);
     else watchdog<=watchdog+1'b1;
    end
    WAIT: begin
     if(rx_valid && rx_match) begin
      case(rx_index)
       0:next_cluster[7:0]<=rx_byte;1:next_cluster[15:8]<=rx_byte;
       2:next_cluster[23:16]<=rx_byte;3:next_cluster[27:24]<=rx_byte[3:0];
      endcase
      seen[rx_index]<=1;
     end
     if(rx_error!=0) fail(8'h42);
     else if(rx_done) state<=CHECK;
     else if(watchdog>=TIMEOUT_CYCLES-1) fail(8'h41);
     else watchdog<=watchdog+1'b1;
    end
    CHECK: begin
     if(seen!=15) fail(8'h43);
     else if(count==needed) begin
      if(next_cluster>=32'h0ffffff8) begin valid<=1;state<=RESULT;end
      else fail(8'h44);
     end else if(next_cluster<2 || next_cluster>last || next_cluster>=32'h0ffffff0 || next_cluster==cluster)
      fail(8'h45);
     else begin cluster<=next_cluster;count<=count+1'b1;watchdog<=0;state<=REQ;end
    end
    RESULT: begin done<=1;state<=IDLE;end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
