`timescale 1ns/1ps
// RPCM v1: header CRC covers bytes 0..27; bytes 28..31 hold CRC32 LE.
// A valid header does not prove payload integrity: owner must verify payload
// before committing, and use payload_crc for checking recorded data on mount.
module record_commit_header(
 input wire clk,rst_n,
 input wire create,input wire [1:0] image,input wire bank,
 input wire [31:0] generation,samples,payload_crc,
 output reg encode_ready,input wire [8:0] encode_index,output reg [7:0] encode_byte,
 input wire read_start,read_valid,input wire [8:0] read_index,
 input wire [7:0] read_byte,input wire read_done,
 output reg checked,valid,
 output reg [31:0] read_generation,read_samples,read_payload_crc
);
 reg [223:0] prefix;
 reg [255:0] received;
 reg [31:0] encode_crc,decode_crc;
 reg [5:0] build_index;
 reg building,reading,order_error,fields_bad;
 reg [9:0] read_count;
 reg [1:0] expected_image;
 reg expected_bank;
 function [31:0] crc_byte;
 input [31:0] crc;input [7:0] octet;
 reg [31:0] c;integer n;
 begin
  c=crc^{24'd0,octet};
  for(n=0;n<8;n=n+1) c=c[0] ? (c>>1)^32'hedb88320 : c>>1;
  crc_byte=c;
 end
 endfunction
 always @* begin
  encode_byte=0;
  if(encode_index<28) encode_byte=prefix[encode_index*8 +: 8];
  else if(encode_index<32) begin
   case(encode_index[1:0])
    0:encode_byte=~encode_crc[7:0];1:encode_byte=~encode_crc[15:8];
    2:encode_byte=~encode_crc[23:16];3:encode_byte=~encode_crc[31:24];
   endcase
  end
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   prefix<=0;received<=0;encode_crc<=32'hffffffff;decode_crc<=32'hffffffff;
   build_index<=0;building<=0;reading<=0;order_error<=0;fields_bad<=0;read_count<=0;
   expected_image<=0;expected_bank<=0;encode_ready<=0;checked<=0;valid<=0;
   read_generation<=0;read_samples<=0;read_payload_crc<=0;
  end else begin
   checked<=0;
   if(create && !building) begin
    // Concatenation is reverse byte order because byte zero is in bits 7:0.
    prefix<={32'd0,payload_crc,32'd48000,samples,generation,
             8'ha5,{7'd0,bank},{6'd0,image},8'd1,32'h4d435052};
    encode_crc<=32'hffffffff;build_index<=0;building<=1;encode_ready<=0;
   end else if(building) begin
    encode_crc<=crc_byte(encode_crc,prefix[build_index*8 +: 8]);
    if(build_index==27) begin building<=0;encode_ready<=1;end
    else build_index<=build_index+1'b1;
   end
   if(read_start) begin
    received<=0;decode_crc<=32'hffffffff;reading<=1;
    read_count<=0;order_error<=0;fields_bad<=0;valid<=0;
    expected_image<=image;expected_bank<=bank;
   end else if(reading) begin
    if(read_valid) begin
     if(read_count>=512 || {1'b0,read_index}!=read_count) order_error<=1;
     if(read_count<512) read_count<=read_count+1'b1;
     // Compare constant/identity fields as they arrive; only retain variable
     // metadata and CRC. This avoids a 256-bit bank of byte-enabled registers.
     case(read_index)
      0:if(read_byte!="R")fields_bad<=1;
      1:if(read_byte!="P")fields_bad<=1;
      2:if(read_byte!="C")fields_bad<=1;
      3:if(read_byte!="M")fields_bad<=1;
      4:if(read_byte!=1)fields_bad<=1;
      5:if(read_byte!={6'd0,expected_image})fields_bad<=1;
      6:if(read_byte!={7'd0,expected_bank})fields_bad<=1;
      7:if(read_byte!=8'ha5)fields_bad<=1;
      16:if(read_byte!=8'h80)fields_bad<=1;
      17:if(read_byte!=8'hbb)fields_bad<=1;
      18,19,24,25,26,27:if(read_byte!=0)fields_bad<=1;
      default:;
     endcase
     if((read_index>=8 && read_index<16) || (read_index>=20 && read_index<24) ||
        (read_index>=28 && read_index<32)) received[read_index*8 +: 8]<=read_byte;
     if(read_index<28) decode_crc<=crc_byte(decode_crc,read_byte);
    end
    // sector_done may coincide with the final (padding) byte.
    if(read_done) begin
     reading<=0;checked<=1;
     valid<=!order_error && !fields_bad &&
       (read_count==512 || (read_count==511 && read_valid && read_index==511)) &&
       received[127:96]!=0 && received[127:96]<=1440000 &&
       received[255:224]==~decode_crc;
     read_generation<=received[95:64];read_samples<=received[127:96];
     read_payload_crc<=received[191:160];
    end
   end
  end
 end
endmodule
