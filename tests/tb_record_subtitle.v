`timescale 1ns/1ps
module tb_record_subtitle;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0;reg [9:0] x=64;reg [1:0] state=0;reg [5:0] seconds=8;
 wire [23:0] rgb;
 scrolling_subtitle dut(.clk(clk),.rst_n(rst_n),.vsync(1'b1),.de(1'b1),.pixel_x(x),
 .page_index(2'd0),.brightness(2'd1),.contrast(2'd1),.auto_mode(1'b0),
 .record_state(state),.record_seconds(seconds),.rgb_in(24'h123456),.rgb_out(rgb));
 integer xx,yy,mode,col,idx,pixels;reg expected;reg [4:0] glyph;
 reg [15:0] rowbits;
 task tick;begin @(posedge clk);#1;end endtask
 initial begin
  repeat(3)tick;rst_n=1;tick;
  force dut.record_scroll=0;
  for(mode=1;mode<=2;mode=mode+1) begin
   force dut.record_state_q=mode;
   force dut.record_seconds_q=8;
   pixels=0;
   for(yy=0;yy<16;yy=yy+1) begin
    force dut.line_y=344+yy;
    x=63;tick;
    for(xx=64;xx<576;xx=xx+1) begin
     x=xx;#1;
     idx=((xx-64)&255)>>4;col=(xx-64)&15;
     glyph=11;
     if(mode==1) case(idx)
      0:glyph=13;1:glyph=14;2:glyph=15;3:glyph=16;4:glyph=12;
      5:glyph=0;6:glyph=0;7:glyph=10;8:glyph=0;9:glyph=8;
      default:glyph=11;
     endcase
     else case(idx) 0:glyph=17;1:glyph=18;2:glyph=19;default:glyph=11;endcase
     rowbits=dut.u_record_font.font_mem[{glyph,4'd0}+yy];
     expected=rowbits[15-col];
     if(dut.hit!==expected) $fatal(1,"subtitle alignment mode %0d x%0d row%0d",mode,xx,yy);
     if(expected) begin
      pixels=pixels+1;
      if(rgb!=24'hffffff) $fatal(1,"subtitle fill");
     end
     tick;
    end
   end
   if(pixels==0) $fatal(1,"no Chinese status pixels");
  end
  // Validate scenery ROM prefetch at each character boundary as well.
  force dut.record_state_q=0;force dut.text_x_q=0;
  for(yy=0;yy<16;yy=yy+1) begin
   force dut.line_y=344+yy;x=63;tick;
   for(xx=64;xx<576;xx=xx+1) begin
    x=xx;#1;
    idx=(xx-64)>>4;col=(xx-64)&15;
    rowbits=dut.text_mem[idx]<119 ? dut.u_jiuzhaigou_font.font_mem[dut.text_mem[idx]*16+yy] : 16'd0;
    if(dut.hit!==rowbits[15-col]) $fatal(1,"scenery prefetch x%0d row%0d",xx,yy);
    tick;
   end
  end
  release dut.text_x_q;
  release dut.line_y;release dut.record_state_q;release dut.record_seconds_q;release dut.record_scroll;
  force dut.record_state_q=0;force dut.line_y=100;x=64;tick;
  if(rgb!=24'h123456) $fatal(1,"video passthrough");
  $display("PASS Chinese subtitle: recording 00:08 and saving repeat with BRAM/pixel alignment");$finish;
 end
endmodule
