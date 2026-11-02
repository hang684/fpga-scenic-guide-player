`timescale 1ns/1ps
module tb_record_scanner #(parameter END_WITH_DATA=0);
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,scan_start=0,sector_busy=0,sector_valid=0,sector_done=0;
 reg [8:0] sector_byte_index=0;reg [7:0] sector_byte=0;
 wire scan_done,sector_req;wire [31:0] sector_lba;
 wire [7:0] record_valid_map,fs_error;wire [255:0] record_clusters,record_sizes;
 reg [7:0] disk[0:1535];integer i,base,j;
 fat32_volume_scanner #(.SCAN_AUDIO_FILE(1),.SCAN_RECORD_FILES(1)) dut(
  .clk(clk),.rst_n(rst_n),.scan_start(scan_start),.scan_done(scan_done),.fs_error(fs_error),
  .record_valid_map(record_valid_map),.record_clusters(record_clusters),.record_sizes(record_sizes),
  .sector_req(sector_req),.sector_lba(sector_lba),.sector_busy(sector_busy),
  .sector_valid(sector_valid),.sector_byte(sector_byte),.sector_byte_index(sector_byte_index),
  .sector_done(sector_done),.sector_error(8'd0));
 task tick;begin @(posedge clk);#1;end endtask
 initial begin
  $readmemh("scanner_disk.hex",disk);
  repeat(3) tick;rst_n=1;tick;scan_start=1;tick;scan_start=0;
  wait(scan_done);#1;
  if(fs_error!=0 || record_valid_map!=255) $fatal(1,"record directory map %h error %h",record_valid_map,fs_error);
  for(j=0;j<8;j=j+1)
   if(record_clusters[j*32 +: 32]!=20+j || record_sizes[j*32 +: 32]!=2880512)
    $fatal(1,"slot metadata %0d",j);
  $display("PASS directory scanner: eight recording slots across root sectors");$finish;
 end
 initial forever begin
  wait(sector_req);#1;
  case(sector_lba) 0:base=0;33:base=512;34:base=1024;default:$fatal(1,"unexpected sector %0d",sector_lba);endcase
  sector_busy=1;
  for(i=0;i<512;i=i+1) begin
   sector_valid=1;sector_byte_index=i;sector_byte=disk[base+i];
   sector_done=END_WITH_DATA && i==511;tick;
  end
  sector_valid=0;
  if(!END_WITH_DATA) begin tick;sector_done=1;tick;end
  sector_done=0;sector_busy=0;tick;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
