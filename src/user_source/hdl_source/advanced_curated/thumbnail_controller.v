// thumbnail_controller.v —— 第14课练习骨架（完赛工程未实现）
module thumbnail_controller (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        key_right,   // 消抖后单拍：焦点右移
    input  wire        key_left,    // 消抖后单拍：焦点左移
    input  wire        key_confirm, // 消抖后单拍：选中当前焦点
    input  wire        key_mode,    // 消抖后单拍：全屏/缩略图切换
    input  wire [3:0]  image_complete,
    input  wire        frame_start, // 帧边界
    output reg         view_mode,   // 0=全屏 1=缩略图
    output reg [1:0]   focus_index,
    output reg [1:0]   active_index,
    output reg         transition_req
);
    reg next_mode;
    reg [1:0] next_focus;
    reg [1:0] next_active;
    reg commit_pending;
    reg transition_pending;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            view_mode          <= 1'b0;
            focus_index        <= 2'd0;
            active_index       <= 2'd0;
            transition_req     <= 1'b0;
            next_mode          <= 1'b0;
            next_focus         <= 2'd0;
            next_active        <= 2'd0;
            commit_pending     <= 1'b0;
            transition_pending <= 1'b0;
        end else begin
            transition_req <= 1'b0;
            if (frame_start && commit_pending) begin
                view_mode          <= next_mode;
                focus_index        <= next_focus;
                active_index       <= next_active;
                transition_req     <= transition_pending;
                commit_pending     <= 1'b0;
                transition_pending <= 1'b0;
            end else if (key_mode) begin
                next_mode          <= ~next_mode;
                commit_pending     <= 1'b1;
                transition_pending <= 1'b1;
            end else if (next_mode && key_confirm && image_complete[next_focus]) begin
                next_active        <= next_focus;
                next_mode          <= 1'b0;
                commit_pending     <= 1'b1;
                transition_pending <= 1'b1;
            end else if (next_mode && key_right) begin
                next_focus     <= next_focus + 2'd1;
                commit_pending <= 1'b1;
            end else if (next_mode && key_left) begin
                next_focus     <= next_focus - 2'd1;
                commit_pending <= 1'b1;
            end
        end
    end
endmodule

