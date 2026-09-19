`timescale 1ns / 1ps
`default_nettype none

// Periodically reports the latest two 12-bit ADC codes as:
// A=ABC,B=DEF\r\n
module adc_hex_reporter #(
    parameter integer unsigned REPORT_INTERVAL_CYCLES = 5_000_000
) (
    input  wire         clk,
    input  wire         rst,
    input  wire [11:0]  sample_a,
    input  wire [11:0]  sample_b,
    input  wire         sample_valid,
    input  wire         tx_ready,
    output logic [7:0]  tx_data,
    output wire         tx_valid
);

    localparam integer unsigned INTERVAL_SAFE =
        (REPORT_INTERVAL_CYCLES < 2) ? 2 : REPORT_INTERVAL_CYCLES;
    localparam integer unsigned COUNTER_WIDTH = $clog2(INTERVAL_SAFE);
    localparam logic [4:0] LAST_INDEX = 5'd12;

    logic [COUNTER_WIDTH-1:0] interval_count;
    logic [11:0] latest_a;
    logic [11:0] latest_b;
    logic [11:0] report_a;
    logic [11:0] report_b;
    logic [4:0]  byte_index;
    logic        have_sample;
    logic        sending;

    function automatic logic [7:0] hex_ascii(input logic [3:0] value);
        if (value < 4'd10)
            hex_ascii = 8'h30 + value;
        else
            hex_ascii = 8'h41 + (value - 4'd10);
    endfunction

    always_comb begin
        case (byte_index)
            5'd0:  tx_data = "A";
            5'd1:  tx_data = "=";
            5'd2:  tx_data = hex_ascii(report_a[11:8]);
            5'd3:  tx_data = hex_ascii(report_a[7:4]);
            5'd4:  tx_data = hex_ascii(report_a[3:0]);
            5'd5:  tx_data = ",";
            5'd6:  tx_data = "B";
            5'd7:  tx_data = "=";
            5'd8:  tx_data = hex_ascii(report_b[11:8]);
            5'd9:  tx_data = hex_ascii(report_b[7:4]);
            5'd10: tx_data = hex_ascii(report_b[3:0]);
            5'd11: tx_data = 8'h0D;
            default: tx_data = 8'h0A;
        endcase
    end

    assign tx_valid = sending;

    always_ff @(posedge clk) begin
        if (rst) begin
            interval_count <= '0;
            latest_a       <= 12'd0;
            latest_b       <= 12'd0;
            report_a       <= 12'd0;
            report_b       <= 12'd0;
            byte_index     <= 5'd0;
            have_sample    <= 1'b0;
            sending        <= 1'b0;
        end
        else begin
            if (sample_valid) begin
                latest_a    <= sample_a;
                latest_b    <= sample_b;
                have_sample <= 1'b1;
            end

            if (sending) begin
                if (tx_ready) begin
                    if (byte_index == LAST_INDEX) begin
                        byte_index <= 5'd0;
                        sending    <= 1'b0;
                    end
                    else begin
                        byte_index <= byte_index + 1'b1;
                    end
                end
            end
            else if (interval_count == INTERVAL_SAFE - 1) begin
                interval_count <= '0;
                if (have_sample) begin
                    report_a   <= latest_a;
                    report_b   <= latest_b;
                    byte_index <= 5'd0;
                    sending    <= 1'b1;
                end
            end
            else begin
                interval_count <= interval_count + 1'b1;
            end
        end
    end

endmodule

`default_nettype wire
