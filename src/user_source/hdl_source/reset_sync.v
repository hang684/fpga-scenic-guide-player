`timescale 1ns / 1ps
// 低有效复位同步器：异步置位，在目标时钟域同步释放。
module reset_sync (
    input  wire clk,         // 本时钟域时钟
    input  wire ext_rst_n,   // 外部异步低有效复位
    output wire rst_n_sync   // 本域同步释放的低有效复位
);
    (* async_reg = "true" *) reg s1, s2;

    always @(posedge clk or negedge ext_rst_n) begin
        if (!ext_rst_n) begin
            s1 <= 1'b0;
            s2 <= 1'b0;
        end else begin
            s1 <= 1'b1;
            s2 <= s1;
        end
    end

    assign rst_n_sync = s2;
endmodule

// 单比特持续电平跨时钟域同步器。
module sync_2ff (
    input  wire clk,
    input  wire rst_n,
    input  wire async_in,
    output wire sync_out
);

    (* async_reg = "true" *) reg s1, s2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1 <= 1'b0;
            s2 <= 1'b0;
        end else begin
            s1 <= async_in;
            s2 <= s1;
        end
    end

    assign sync_out = s2;

endmodule
