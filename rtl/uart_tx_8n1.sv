`timescale 1ns / 1ps
`default_nettype none

module uart_tx_8n1 #(
    parameter integer unsigned CLK_HZ = 50_000_000,
    parameter integer unsigned BAUD   = 115_200
) (
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] data,
    input  wire       valid,
    output logic      ready,
    output logic      tx
);

    localparam integer unsigned CLKS_PER_BIT =
        (CLK_HZ + (BAUD / 2)) / BAUD;

    localparam integer unsigned BAUD_COUNT_WIDTH =
        (CLKS_PER_BIT <= 1) ? 1 : $clog2(CLKS_PER_BIT);

    logic [9:0] shift_reg;
    logic [3:0] bit_index;
    logic [BAUD_COUNT_WIDTH-1:0] baud_count;
    logic busy;

    always_comb begin
        ready = !busy;
        tx    = busy ? shift_reg[0] : 1'b1;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            shift_reg <= 10'h3FF;
            bit_index <= 4'd0;
            baud_count <= '0;
            busy <= 1'b0;
        end
        else if (!busy) begin
            if (valid) begin
                shift_reg <= {1'b1, data, 1'b0};
                bit_index  <= 4'd0;
                baud_count <= '0;
                busy       <= 1'b1;
            end
        end
        else if (baud_count == CLKS_PER_BIT - 1) begin
            baud_count <= '0;

            if (bit_index == 4'd9) begin
                busy <= 1'b0;
            end
            else begin
                shift_reg <= {1'b1, shift_reg[9:1]};
                bit_index <= bit_index + 1'b1;
            end
        end
        else begin
            baud_count <= baud_count + 1'b1;
        end
    end

endmodule

`default_nettype wire
