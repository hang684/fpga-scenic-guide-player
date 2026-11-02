`timescale 1ns/1ps
module tb_record_menu;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,frame=0;reg [11:0] x=0,y=0;
 reg [2:0] menu=0;wire [11:0] rgb;wire hit;
 status_osd_overlay dut(.clk(clk),.rst_n(rst_n),.frame_start(frame),.active_index(2'd0),
 .auto_enabled(1'b0),.volume(8'd255),.error_code(8'd0),.adjust_menu(menu),
 .record_enabled(1'b1),.record_state(2'd1),.record_seconds(6'd8),.record_error(8'd0),
 .brightness_level(2'd1),.contrast_level(2'd1),.period_level(3'd1),.config_status(2'd0),
 .in_de(1'b1),.in_rgb(12'h123),.pixel_x(x),.pixel_y(y),.out_rgb(rgb),.osd_pixel(hit));
 integer xx,yy,pass_n;reg expected,center;integer count_white=0,count_black=0,count_yellow=0;
 initial begin
  #12;rst_n=1;
  for(pass_n=0;pass_n<2;pass_n=pass_n+1) begin
   menu=pass_n==0?0:4;frame=1;@(posedge clk);#1;frame=0;
   for(yy=26;yy<67;yy=yy+1) for(xx=5;xx<43;xx=xx+1) begin
    x=xx;y=yy;#1;
    center=dut.glyph_at(x,y);
    expected=0;
    if(y>=27 && y<66)
     expected=dut.glyph_at(x-1,y-1)|dut.glyph_at(x,y-1)|dut.glyph_at(x+1,y-1)|
      dut.glyph_at(x-1,y)|dut.glyph_at(x+1,y)|
      dut.glyph_at(x-1,y+1)|dut.glyph_at(x,y+1)|dut.glyph_at(x+1,y+1);
    if(hit!==(center|expected)) $fatal(1,"outline mismatch at %0d,%0d",x,y);
    if(center && y>=28 && y<66) begin
     if(pass_n==1 && y>=58) begin
      if(rgb!=12'hff0) $fatal(1,"selected R color");count_yellow=count_yellow+1;
     end else begin
      if(rgb!=12'hfff) $fatal(1,"ordinary menu color");count_white=count_white+1;
     end
    end else if(expected && !center) begin
     if(rgb!=0) $fatal(1,"outline not black");count_black=count_black+1;
    end
   end
  end
  if(count_white==0 || count_black==0 || count_yellow==0) $fatal(1,"empty menu");
  $display("PASS menu: all glyph interiors, selected R and full eight-neighbor black outline");$finish;
 end
endmodule
