`timescale 1ns / 1ps
`default_nettype none

module uart_reporter (
    input  wire         clk,
    input  wire         rst,
    input  wire         report_valid,
    output logic        report_ready,
    input  wire [1:0]   report_direction,
    input  wire [63:0]  report_speed_mm_s,
    output logic [7:0]  tx_data,
    output logic        tx_valid,
    input  wire         tx_ready
);

    localparam logic [1:0] DIR_FWD = 2'd1;
    localparam integer unsigned MESSAGE_LENGTH = 8;

    logic sending;
    logic [3:0] message_index;
    logic [7:0] direction_char;
    logic [7:0] digit_thousands;
    logic [7:0] digit_hundreds;
    logic [7:0] digit_tens;
    logic [7:0] digit_ones;
    logic [13:0] speed_clip;
    logic [3:0] number_thousands;
    logic [3:0] number_hundreds;
    logic [3:0] number_tens;
    logic [3:0] number_ones;

    always_comb begin
        if (report_speed_mm_s > 64'd9999) begin
            speed_clip = 14'd9999;
        end
        else begin
            speed_clip = report_speed_mm_s[13:0];
        end

        number_thousands = speed_clip / 1000;
        number_hundreds  = (speed_clip / 100) % 10;
        number_tens      = (speed_clip / 10) % 10;
        number_ones      = speed_clip % 10;
    end

    always_comb begin
        report_ready = !sending;
        tx_valid     = sending;

        case (message_index)
            4'd0: tx_data = direction_char;
            4'd1: tx_data = 8'h2C;
            4'd2: tx_data = digit_thousands;
            4'd3: tx_data = digit_hundreds;
            4'd4: tx_data = digit_tens;
            4'd5: tx_data = digit_ones;
            4'd6: tx_data = 8'h0D;
            default: tx_data = 8'h0A;
        endcase
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            sending         <= 1'b0;
            message_index    <= 4'd0;
            direction_char   <= 8'h3F;
            digit_thousands  <= 8'h30;
            digit_hundreds   <= 8'h30;
            digit_tens       <= 8'h30;
            digit_ones       <= 8'h30;
        end
        else if (!sending && report_valid) begin
            direction_char <=
                (report_direction == DIR_FWD) ? 8'h46 : 8'h52;
            digit_thousands <= {4'h3, number_thousands};
            digit_hundreds  <= {4'h3, number_hundreds};
            digit_tens      <= {4'h3, number_tens};
            digit_ones      <= {4'h3, number_ones};
            message_index   <= 4'd0;
            sending         <= 1'b1;
        end
        else if (sending && tx_ready) begin
            if (message_index == MESSAGE_LENGTH - 1) begin
                sending       <= 1'b0;
                message_index <= 4'd0;
            end
            else begin
                message_index <= message_index + 1'b1;
            end
        end
    end

endmodule

`default_nettype wire
