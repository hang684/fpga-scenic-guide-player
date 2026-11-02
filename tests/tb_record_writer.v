`timescale 1ns/1ps
module tb_record_writer #(parameter CORRUPT=0,parameter BAD_CHAIN=0);
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,start=0,stop=0,bank=0,allocation_checked=1,sample_valid=0,bus_idle=1;
 reg [1:0] image=0;reg [31:0] generation=1,first_cluster=5;
 reg [7:0] sectors_per_cluster=1;reg [31:0] fat_start_lba=32,data_start_lba=100,max_cluster=1000;
 reg [15:0] sample=0;
 reg read_valid=0,read_end=0,write_byte_req=0,write_end=0;
 reg [8:0] read_index=0;reg [7:0] read_byte=0,read_error=0;
 wire busy,recording,done,success,read_req,write_req;
 wire [31:0] samples_captured,saved_samples,read_lba,write_lba;
 wire [7:0] error,write_byte;
 wire external_cursor_mode=0,external_cursor_open=0,external_cursor_advance=0;
 wire [31:0] external_first_cluster=0;
 wire shared_cursor_busy,shared_cursor_valid,shared_cursor_failed;
 wire [31:0] shared_cursor_lba;wire [7:0] shared_cursor_error;
 record_file_writer #(.SLOT_BYTES(1536)) dut(.*);
 always @(posedge clk) if(dut.verifier.compare_pending && dut.verifier.actual!==dut.verifier.expected)
  $display("mismatch read_lba=%0d count=%0d actual=%h expected=%h",read_lba,dut.verifier.read_count,dut.verifier.actual,dut.verifier.expected);
 reg [7:0] disk[0:2047];integer i,j,k,base,writes;reg [7:0] expected;
 task tick;begin @(posedge clk);#1;end endtask
 function integer offset;
 input [31:0] lba;
 begin case(lba) 103:offset=0;107:offset=512;104:offset=1024;32:offset=1536;default:offset=-1;endcase end
 endfunction
 initial begin
  writes=0;
  for(k=0;k<2048;k=k+1) disk[k]=0;
  disk[1536+20]=9;disk[1536+36]=6;
  disk[1536+24]=255;disk[1536+25]=255;disk[1536+26]=255;disk[1536+27]=15;
  if(BAD_CHAIN) begin
   disk[0]=8'h5a;disk[1536+24]=9;disk[1536+25]=0;disk[1536+26]=0;disk[1536+27]=0;
  end
  repeat(3) tick;rst_n=1;tick;start=1;tick;start=0;
  if(BAD_CHAIN) begin
   wait(done);#1;
   if(success || writes!=0 || error!=8'h44 || disk[0]!=8'h5a)
    $fatal(1,"bad allocation modified card");
   $display("PASS file writer: cyclic allocation rejected before any write");$finish;
  end
  wait(recording);#1;
  for(j=0;j<300;j=j+1) begin
   sample=16'h8100+j;sample_valid=1;tick;sample_valid=0;repeat(4) tick;
  end
  stop=1;tick;stop=0;
  wait(done);#1;
  if(CORRUPT) begin
   if(success || error!=8'h15 || writes!=2 || disk[7]!=0)
    $fatal(1,"failed payload was committed");
   $display("PASS file writer: corrupt write rejected, invalid header retained");$finish;
  end
  if(!success || error!=0 || saved_samples!=300 || writes!=4)
   $fatal(1,"writer result success %b error %h samples %0d writes %0d",success,error,saved_samples,writes);
  if({disk[3],disk[2],disk[1],disk[0]}!=32'h4d435052 || disk[7]!=8'ha5 ||
     {disk[15],disk[14],disk[13],disk[12]}!=300) $fatal(1,"commit header");
  for(j=0;j<1024;j=j+1) begin
   if(j>=600) expected=0;
   else if(j%2==0) expected=(16'h8100+j/2)&255;
   else expected=(16'h8100+j/2)>>8;
   if(disk[512+j]!==expected) $fatal(1,"saved PCM byte %0d got %h expected %h",j,disk[512+j],expected);
  end
  $writememh("writer_card.hex",disk);
  $display("PASS file writer: fragmented A/B slot, PCM persistence, verified header-last commit");$finish;
 end
 initial forever begin
  wait(write_req || read_req);#1;
  bus_idle=0;
  if(write_req) begin
   base=offset(write_lba);if(base<0 || base>=1536) $fatal(1,"illegal write LBA %0d",write_lba);
   if(writes==0 && write_lba!=103) $fatal(1,"invalidate first");
   if(writes>0 && writes<3 && write_lba==103) $fatal(1,"header committed early");
   writes=writes+1;
   for(i=0;i<512;i=i+1) begin
    write_byte_req=1;tick;write_byte_req=0;disk[base+i]=write_byte;tick;
   end
   write_end=1;tick;write_end=0;
   if(CORRUPT && writes==2) disk[base+511]=disk[base+511]^1;
  end else begin
   base=offset(read_lba);if(base<0) $fatal(1,"illegal read LBA %0d",read_lba);
   for(i=0;i<512;i=i+1) begin
    read_valid=1;read_index=i;read_byte=disk[base+i];tick;
   end
   read_valid=0;tick;read_end=1;tick;read_end=0;
  end
  bus_idle=1;tick;
 end
 initial begin #2000000;$fatal(1,"timeout state %0d",dut.state);end
endmodule
