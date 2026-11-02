`timescale 1ns/1ps
module tb_record_manager #(parameter CORRUPT=0);
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,mount_start=0,record_start=0,record_stop=0;
 reg [1:0] image=0;reg [7:0] slot_valid=3;
 reg [255:0] slot_clusters=0;
 reg [7:0] sectors_per_cluster=1;
 reg [31:0] fat_start_lba=32,data_start_lba=100,max_cluster=1000;
 reg sample_valid=0;reg [15:0] sample=0;reg bus_idle=1;
 wire busy,recording,ready,changed,recover_required;
 wire [7:0] error;wire [31:0] sample_count;
 wire [3:0] selected_valid,selected_bank;
 wire [127:0] selected_clusters,selected_bytes;
 wire read_req,write_req;wire [31:0] read_lba,write_lba;wire [7:0] write_byte;
 reg read_valid=0,read_end=0;reg [8:0] read_index=0;
 reg [7:0] read_byte=0,read_error=0;reg write_byte_req=0,write_end=0;
 recording_manager #(.SLOT_BYTES(1536),.TIMEOUT_CYCLES(10000)) dut(.*);
 reg [7:0] disk[0:3583];integer i,base,j;
 task tick;begin @(posedge clk);#1;end endtask
 initial begin
  $readmemh("manager_card.hex",disk);
  slot_clusters[31:0]=5;slot_clusters[63:32]=20;
  if(CORRUPT>=1) disk[2048]=disk[2048]^1;
  if(CORRUPT==2) disk[512]=disk[512]^1;
  repeat(3) tick;rst_n=1;tick;mount_start=1;tick;mount_start=0;
  wait(ready);#1;
  if(error!=0 || recover_required) $fatal(1,"mount error %h",error);
  if(CORRUPT==2) begin
   if(selected_valid!=0) $fatal(1,"corrupt recordings selected");
  end else begin
   if(selected_valid!=1 || selected_bank[0]!=(CORRUPT==0) ||
      selected_clusters[31:0]!=(CORRUPT==0?20:5) ||
      selected_bytes[31:0]!=(CORRUPT==0?200:600)) $fatal(1,"wrong A/B selection");
  end
  $display("PASS mount manager: A/B generation wrap, CRC validation, fallback trial %0d",CORRUPT);
  if(CORRUPT!=0) $finish;
  record_start=1;tick;record_start=0;
  wait(recording);#1;
  for(j=0;j<100;j=j+1) begin
   sample=16'h9876+j;sample_valid=1;tick;sample_valid=0;repeat(4)tick;
  end
  record_stop=1;tick;record_stop=0;
  wait(changed);#1;
  if(selected_valid!=1 || selected_bank[0]!=0 || selected_bytes[31:0]!=200 || selected_clusters[31:0]!=5)
   $fatal(1,"replacement metadata");
  tick;mount_start=1;tick;mount_start=0;
  wait(ready);#1;
  if(selected_valid!=1 || selected_bank[0]!=0 || selected_bytes[31:0]!=200)
   $fatal(1,"replacement did not survive remount");
  $display("PASS manager recording transaction: inactive bank, replacement, remount persistence");$finish;
 end
 initial forever begin
  wait(read_req || write_req);#1;
  case(write_req?write_lba:read_lba)
   103:base=0;107:base=512;104:base=1024;
   118:base=1536;119:base=2048;120:base=2560;32:base=3072;
   default:$fatal(1,"unexpected LBA %0d",read_lba);
  endcase
  bus_idle=0;
  if(write_req) begin
   if(base>=3072) $fatal(1,"write FAT forbidden");
   for(i=0;i<512;i=i+1) begin
    write_byte_req=1;tick;write_byte_req=0;disk[base+i]=write_byte;tick;
   end
   write_end=1;tick;write_end=0;
  end else begin
   for(i=0;i<512;i=i+1) begin read_valid=1;read_index=i;read_byte=disk[base+i];tick;end
   read_valid=0;tick;read_end=1;tick;read_end=0;
  end
  bus_idle=1;tick;
 end
 initial begin #1000000;$fatal(1,"timeout state %0d",dut.state);end
endmodule
