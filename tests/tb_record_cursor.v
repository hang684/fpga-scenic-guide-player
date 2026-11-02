`timescale 1ns/1ps
module tb_record_cursor;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,open=0,advance=0,cancel=0,sector_busy=0,sector_valid=0,sector_done=0;
 reg [31:0] first_cluster=5,file_bytes=3072,fat_start_lba=32,data_start_lba=100,max_cluster=1000;
 reg [7:0] sectors_per_cluster=2,sector_byte=0,sector_error=0;
 reg [8:0] sector_byte_index=0;
 wire busy,lba_valid,failed,sector_req;wire [31:0] lba,sector_number,sector_lba;wire [7:0] error;
 record_fat_cursor #(.TIMEOUT_CYCLES(1000)) dut(.*);
 integer i;reg [31:0] link;
 task tick;begin @(posedge clk);#1;end endtask
 task next_sector;
 begin advance=1;tick;advance=0;end
 endtask
 task fat_reply;
 input [31:0] cluster,value;
 begin
  wait(sector_req);#1;
  if(sector_lba!=32+(cluster>>7)) $fatal(1,"FAT LBA");
  sector_busy=1;
  for(i=0;i<4;i=i+1) begin
   sector_valid=1;sector_byte_index=(cluster%128)*4+i;sector_byte=value>>(i*8);tick;
  end
  sector_valid=0;sector_done=1;tick;sector_done=0;sector_busy=0;
 end
 endtask
 initial begin
  repeat(3) tick;rst_n=1;tick;open=1;tick;open=0;
  wait(lba_valid);#1;if(lba!=106 || sector_number!=0) $fatal(1,"header LBA");
  next_sector;if(lba!=107) $fatal(1,"same cluster");
  next_sector;fat_reply(5,32'hf0000009);
  wait(lba_valid);#1;if(lba!=114 || sector_number!=2) $fatal(1,"fragmented chain");
  next_sector;if(lba!=115) $fatal(1,"second cluster");
  next_sector;fat_reply(9,32'h0fffffff);
  wait(failed);if(error!=5) $fatal(1,"truncated chain accepted");
  $display("PASS FAT cursor: fragmented chain, reserved nibble, premature EOF");$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
