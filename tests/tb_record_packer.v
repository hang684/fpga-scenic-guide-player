`timescale 1ns/1ps
module tb_record_packer #(parameter AUTOSTOP=0);
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,start=0,stop=0,sample_valid=0,writer_ready=0,byte_request=0,sector_done=0;
 reg [15:0] sample=0;
 wire [7:0] byte_data;wire sector_request,active,drained,failed;
 wire [31:0] samples_captured,sectors_written;
 record_sector_packer #(.MAX_SAMPLES(AUTOSTOP?300:1440000)) dut(.*);
 integer i,j,n;reg [7:0] expected;
 task tick;begin @(posedge clk);#1;end endtask
 initial begin
  repeat(3) tick;rst_n=1;tick;start=1;tick;start=0;
  for(i=0;i<(AUTOSTOP?320:300);i=i+1) begin sample=16'h8100+i;sample_valid=1;tick;end
  sample_valid=0;stop=!AUTOSTOP;tick;stop=0;writer_ready=1;
  for(n=0;n<2;n=n+1) begin
   wait(sector_request);#1;writer_ready=0;
   for(j=0;j<512;j=j+1) begin
    byte_request=1;tick;byte_request=0;
    i=n*256+j/2;
    if(i>=300) expected=0;
    else if(j%2==0) expected=(16'h8100+i)&255;
    else expected=(16'h8100+i)>>8;
    if(byte_data!==expected) $fatal(1,"PCM byte %0d got %h expected %h",n*512+j,byte_data,expected);
    tick;
   end
   sector_done=1;tick;sector_done=0;writer_ready=1;
  end
  wait(drained);#1;
  if(failed || samples_captured!=300 || sectors_written!=2) $fatal(1,"packer count/failure");
  $display("PASS packer: signed PCM order, two sectors, partial padding and stop");$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
