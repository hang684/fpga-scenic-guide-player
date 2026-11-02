`timescale 1ns/1ps
module tb_record_i2s #(parameter SYS_HZ=100000000);
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,sd=0;wire sck,ws,ready,sample_valid;
 wire signed [23:0] sample24;wire signed [15:0] sample16;
 inmp441_i2s_rx #(.STARTUP_FRAMES(2),.CLK_HZ(SYS_HZ)) dut(.*);
 reg previous_ws=1;integer bit_number=0,count=0,cycles=0,last_cycle=0;
 reg previous_valid=0;
 reg [23:0] left_word=24'h812345;
 reg [23:0] right_word=24'h7abcde;
 // Behavioral microphone: WS transition, one-bit I2S delay, then 24 data bits.
 always @(negedge sck) if(rst_n) begin
  #2;
  if(ws!=previous_ws) bit_number=0;else bit_number=bit_number+1;
  previous_ws=ws;
  if(bit_number>=1 && bit_number<=24)
   sd=ws?right_word[24-bit_number]:left_word[24-bit_number];
  else sd=0;
 end
 always @(posedge clk) begin
  #1;cycles=cycles+1;
  if(sample_valid) begin
   if(!ready || previous_valid || sample24!==left_word || sample16!==left_word[23:8])
    $fatal(1,"I2S sample got %h / %h",sample24,sample16);
   if(count!=0 && cycles-last_cycle!=(SYS_HZ/48000) && cycles-last_cycle!=((SYS_HZ+47999)/48000))
    $fatal(1,"sample rate interval %0d",cycles-last_cycle);
   last_cycle=cycles;count=count+1;
   // Change sign and bit pattern after each sample to expose stale/shifted data.
   left_word=(left_word==24'h812345) ? 24'h123456 : 24'h812345;
   if(count==8) begin
    $display("PASS I2S: left channel, one-bit delay, signed PCM, 48 kHz strobe");$finish;
   end
  end
  previous_valid=sample_valid;
 end
 initial begin repeat(3) @(negedge clk);rst_n=1;end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
