`timescale 1ns/1ps
module tb_record_header;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,create=0,bank=1,read_start=0,read_valid=0,read_done=0;
 reg [1:0] image=2;
 reg [31:0] generation=32'hffffffff,samples=12345,payload_crc=32'h89abcdef;
 reg [8:0] encode_index=0,read_index=0;
 reg [7:0] read_byte=0;
 wire encode_ready,checked,valid;wire [7:0] encode_byte;
 wire [31:0] read_generation,read_samples,read_payload_crc;
 reg [7:0] golden[0:511];integer i,trial;
 record_commit_header dut(.*);
 task tick;begin @(posedge clk);#1;end endtask
 initial begin
  $readmemh("header_golden.hex",golden);
  repeat(3) tick;rst_n=1;tick;create=1;tick;create=0;
  wait(encode_ready);#1;
  for(i=0;i<512;i=i+1) begin
   encode_index=i;#1;
   if(encode_byte!==golden[i]) $fatal(1,"header byte %0d got %h expected %h",i,encode_byte,golden[i]);
  end
  for(trial=0;trial<3;trial=trial+1) begin
   read_start=1;tick;read_start=0;
   for(i=0;i<512;i=i+1) begin
    read_index=i;read_byte=golden[i];
    if(trial==1 && i==12) read_byte=read_byte^1;
    if(trial==2 && i==5) read_byte=0;
    read_valid=1;read_done=i==511;tick;
   end
   read_valid=0;read_done=0;
   if(!checked || valid!==(trial==0)) $fatal(1,"header validation trial %0d",trial);
   if(trial==0 && (read_generation!=generation || read_samples!=samples || read_payload_crc!=payload_crc))
    $fatal(1,"header metadata");
   tick;
  end
  $display("PASS header: Python CRC reference, encode/decode, corrupt metadata rejected");$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
