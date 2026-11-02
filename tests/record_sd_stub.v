
module sd_card_top
#(
	parameter  SPI_LOW_SPEED_DIV = 248,         // SD card low speed mode frequency division parameter,spi clk speed = clk speed /((SPI_LOW_SPEED_DIV + 2) * 2 )
	parameter  SPI_HIGH_SPEED_DIV = 0           // SD card high speed mode frequency division parameter,spi clk speed = clk speed /((SPI_HIGH_SPEED_DIV + 2) * 2 )
)
(
	input            clk,
	input            rst,
	output           SD_nCS,                    //SD card chip select (SPI mode)
	output           SD_DCLK,                   //SD card clock
	output           SD_MOSI,                   //SD card controller data output
	input            SD_MISO,                   //SD card controller data input
	output reg           sd_init_done,              //SD card initialization is complete
	input            sd_sec_read,               //SD card sector read
	input[31:0]      sd_sec_read_addr,          //SD card sector read address
	output reg[7:0]      sd_sec_read_data,          //SD card sector read data
	output reg           sd_sec_read_data_valid,    //SD card sector read data valid
	output reg           sd_sec_read_end,           //SD card sector read end
	input            sd_sec_write,              //SD card sector write
	input[31:0]      sd_sec_write_addr,         //SD card sector write address
	input[7:0]       sd_sec_write_data,         //SD card sector write data
	output reg           sd_sec_write_data_req,     //SD card sector write data next clock is valid
	output reg           sd_sec_write_end           //SD card sector write end
);
reg [2:0] st=0,phase=0;
reg [8:0] idx=0;
reg [31:0] lba=0;
reg [7:0] mem[0:1535];
integer n,off;reg [31:0] link;
assign SD_nCS=1;assign SD_DCLK=0;assign SD_MOSI=0;
initial for(n=0;n<1536;n=n+1)mem[n]=0;
always @(posedge clk) begin
 sd_sec_read_data_valid<=0;sd_sec_read_end<=0;sd_sec_write_data_req<=0;sd_sec_write_end<=0;
 sd_init_done<=!rst;
 if(rst) begin st<=0;idx<=0;phase<=0;end
 else case(st)
 0:begin
  if(sd_sec_read && sd_sec_write)$fatal(1,"simultaneous SD commands");
  if(sd_sec_read || sd_sec_write) begin
   lba<=sd_sec_read?sd_sec_read_addr:sd_sec_write_addr;idx<=0;phase<=0;
   st<=sd_sec_read?1:2;
  end
 end
 1:begin
  if(phase==0)begin phase<=1;end
  else begin
   phase<=0;sd_sec_read_data_valid<=1;
   if(lba==32)begin
    link=(idx/4>=5 && idx/4<48)?idx/4+1:idx/4==48?32'h0fffffff:0;
    sd_sec_read_data<=link>>(idx[1:0]*8);
   end else begin
    if(lba<484 || lba>486)$fatal(1,"unexpected read LBA %0d",lba);
    sd_sec_read_data<=mem[(lba-484)*512+idx];
   end
   if(idx==511)st<=3;else idx<=idx+1'b1;
  end
 end
 2:begin
  if(lba<484 || lba>486)$fatal(1,"write outside reserved data %0d",lba);
  case(phase)
   0:begin sd_sec_write_data_req<=1;phase<=1;end
   1:phase<=2;
   2:begin
    mem[(lba-484)*512+idx]<=sd_sec_write_data;phase<=0;
    if(idx==511)st<=4;else idx<=idx+1'b1;
   end
  endcase
 end
 3:begin sd_sec_read_end<=1;st<=0;end
 4:begin sd_sec_write_end<=1;st<=0;end
 endcase
end
endmodule
