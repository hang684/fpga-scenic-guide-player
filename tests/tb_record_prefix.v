`timescale 1ns/1ps
module tb_record_prefix #(parameter PREFIX=1);
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,file_start=0,pause=0,prefix_mode=PREFIX;
 wire file_busy,file_done,file_valid,sector_req;
 wire [7:0] file_byte,fs_error;wire [31:0] file_byte_offset,sector_lba;
 reg sector_busy=0,sector_valid=0,sector_done=0;
 reg [7:0] sector_byte=0;reg [8:0] sector_byte_index=0;
 fat32_file_streamer #(.ALLOW_PREFIX(1),.PAUSE_ENABLE(1)) dut(
  .clk(clk),.rst_n(rst_n),.file_start(file_start),.pause(pause),.prefix_mode(prefix_mode),
  .first_cluster(32'd5),.file_size(32'd1112),.sectors_per_cluster(8'd1),
  .fat_start_lba(32'd32),.data_start_lba(32'd100),.max_cluster(32'd1000),
  .file_busy(file_busy),.file_done(file_done),.file_valid(file_valid),.file_byte(file_byte),
  .file_byte_offset(file_byte_offset),.fs_error(fs_error),.sector_req(sector_req),.sector_lba(sector_lba),
  .sector_busy(sector_busy),.sector_valid(sector_valid),.sector_byte(sector_byte),
  .sector_byte_index(sector_byte_index),.sector_done(sector_done),.sector_error(8'd0));
 integer i,base,count=0,requests=0;
 task tick;begin @(posedge clk);#1;end endtask
 always @(negedge clk) if(file_valid) begin
  if(file_byte_offset!=count || file_byte!==(count&255)) $fatal(1,"file byte/order %0d",count);
  count=count+1;
 end
 initial begin
  repeat(3) tick;rst_n=1;tick;file_start=1;tick;file_start=0;
  wait(file_done);#2;
  if(fs_error!=0 || count!=1112 || requests!=(PREFIX?5:6))
   $fatal(1,"prefix result bytes %0d requests %0d error %h",count,requests,fs_error);
  $display("PASS file streamer: exact recording length, prefix mode %0d",PREFIX);$finish;
 end
 initial forever begin
  wait(sector_req);#1;requests=requests+1;sector_busy=1;
  case(sector_lba) 103:base=0;107:base=512;104:base=1024;32:base=-1;default:$fatal(1,"LBA");endcase
  for(i=0;i<512;i=i+1) begin
   sector_valid=1;sector_byte_index=i;
   if(base>=0) sector_byte=(base+i)&255;
   else case(i)
    20:sector_byte=9;36:sector_byte=6;
    // Longer preallocated chain: prefix mode must not demand EOF here.
    24:sector_byte=255;25:sector_byte=255;26:sector_byte=255;27:sector_byte=15;
    default:sector_byte=0;
   endcase
   tick;
  end
  sector_valid=0;tick;sector_done=1;tick;sector_done=0;sector_busy=0;tick;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
