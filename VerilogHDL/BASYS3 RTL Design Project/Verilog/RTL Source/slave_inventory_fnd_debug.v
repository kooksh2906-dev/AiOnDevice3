`timescale 1ns / 1ps

// Debug-only vending database. Initial availability is 5'b11101:
// apple=1, orange=1, mango=1, grape=0, pineapple=1.
module slave_inventory_fnd_debug (
    input  wire        clk,
    input  wire        arst,
    input  wire        i_ctrl_trigger,
    input  wire [31:0] i_order_info,
    input  wire [31:0] i_money_in,
    output reg  [31:0] o_status,
    output wire [31:0] o_inventory,
    output reg  [31:0] o_change
);
    reg [13:0] db_price [0:4];
    reg [3:0]  db_stock [0:4];

    reg i_ctrl_trigger_prev;
    wire trigger_pulse;

    reg [13:0] target_price;
    reg [3:0]  target_stock;
    reg [2:0]  target_idx;
    reg        is_valid_order;

    wire all_sold_out;

    assign trigger_pulse = i_ctrl_trigger & ~i_ctrl_trigger_prev;

    always @(*) begin
        is_valid_order = 1'b1;
        case (i_order_info[14:10])
            5'b10000: begin
                target_idx = 3'd0; target_price = db_price[0];
                target_stock = db_stock[0];
            end
            5'b01000: begin
                target_idx = 3'd1; target_price = db_price[1];
                target_stock = db_stock[1];
            end
            5'b00100: begin
                target_idx = 3'd2; target_price = db_price[2];
                target_stock = db_stock[2];
            end
            5'b00010: begin
                target_idx = 3'd3; target_price = db_price[3];
                target_stock = db_stock[3];
            end
            5'b00001: begin
                target_idx = 3'd4; target_price = db_price[4];
                target_stock = db_stock[4];
            end
            default: begin
                target_idx = 3'd0; target_price = 14'd0;
                target_stock = 4'd0; is_valid_order = 1'b0;
            end
        endcase
    end

    always @(posedge clk or posedge arst) begin
        if (arst) begin
            db_price[0] <= 14'd1200; db_stock[0] <= 4'd1;
            db_price[1] <= 14'd1500; db_stock[1] <= 4'd1;
            db_price[2] <= 14'd1700; db_stock[2] <= 4'd1;
            db_price[3] <= 14'd1900; db_stock[3] <= 4'd0;
            db_price[4] <= 14'd2300; db_stock[4] <= 4'd1;

            o_status            <= 32'd0;
            o_change            <= 32'd0;
            i_ctrl_trigger_prev <= 1'b0;
        end
        else begin
            i_ctrl_trigger_prev <= i_ctrl_trigger;

            if (trigger_pulse) begin
                if (!is_valid_order) begin
                    o_status <= 32'd2;
                    o_change <= 32'd0;
                end
                else if (target_stock == 4'd0) begin
                    o_status <= 32'd3;
                    o_change <= 32'd0;
                end
                else if (i_money_in >= {18'd0, target_price}) begin
                    o_status <= 32'd1;
                    o_change <= i_money_in - {18'd0, target_price};
                    db_stock[target_idx] <= db_stock[target_idx] - 4'd1;
                end
                else begin
                    o_status <= 32'd2;
                    o_change <= 32'd0;
                end
            end
        end
    end

    assign all_sold_out = (db_stock[0] == 0) &&
                          (db_stock[1] == 0) &&
                          (db_stock[2] == 0) &&
                          (db_stock[3] == 0) &&
                          (db_stock[4] == 0);

    assign o_inventory = {
        all_sold_out,
        15'd0,
        1'b0,
        (db_stock[0] > 0),
        (db_stock[1] > 0),
        (db_stock[2] > 0),
        (db_stock[3] > 0),
        (db_stock[4] > 0),
        10'd0
    };
endmodule
