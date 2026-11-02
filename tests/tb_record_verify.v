`timescale 1ns/1ps
module tb_record_verify;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,clear=0,load_valid=0,start=0,bus_idle=1;
 reg [8:0] load_index=0,read_index=0;
 reg [7:0] load_byte=0,read_byte=0,read_error=0;
 reg [31:0] target_lba=123;
 reg write_byte_req=0,write_end=0,read_valid=0,read_end=0;
 wire loaded,busy,done,success,write_req,read_req;
 wire [7:0] error,write_byte;wire [31:0] write_lba,read_lba;
 record_sector_verify #(.TIMEOUT_CYCLES(10000)) dut(.*);
 integer i,trial;reg [7:0] expected;
 task tick;begin @(posedge clk);#1;end endtask
 initial begin
  repeat(3) tick;rst_n=1;tick;
  for(trial=0;trial<3;trial=trial+1) begin
   clear=1;tick;clear=0;
   for(i=0;i<512;i=i+1) begin load_index=i;load_byte=i^8'ha6;load_valid=1;tick;end
   load_valid=0;if(!loaded) $fatal(1,"not loaded");
   start=1;tick;start=0;
   wait(write_req);#1;if(write_lba!=123) $fatal(1,"write lba");
   for(i=0;i<512;i=i+1) begin
    write_byte_req=1;tick;write_byte_req=0;expected=i^8'ha6;
    if(write_byte!==expected) $fatal(1,"write data %0d",i);tick;
   end
   write_end=1;tick;write_end=0;
   wait(read_req);#1;if(read_lba!=123) $fatal(1,"verify lba");
   for(i=0;i<512;i=i+1) begin
    read_valid=1;read_index=i;read_byte=i^8'ha6;
    if(trial==1 && i==511) read_byte=read_byte^1;
    if(trial==2 && i==0) read_byte=read_byte^1;
    read_end=i==511;tick;
   end
   read_valid=0;read_end=0;wait(done);#1;
   if(success!==(trial==0)) $fatal(1,"verify trial %0d success %b",trial,success);
   tick;
  end
  $display("PASS sector verify: all bytes, first/last-byte corruption rejected");$finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
