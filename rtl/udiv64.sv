`timescale 1ns / 1ps
`default_nettype none

module udiv64 (
    input  wire         clk,
    input  wire         rst,
    input  wire         start,
    input  wire [63:0]  numerator,
    input  wire [63:0]  denominator,

    output logic        busy,
    output logic        done,
    output logic [63:0] quotient,
    output logic        divide_by_zero
);

    logic [127:0] remainder_quotient;
    logic [63:0]  denominator_reg;
    logic [5:0]   iteration;

    logic [127:0] shifted_value;
    logic [127:0] next_value;

    // Restoring division, one quotient bit per clock cycle.
    always_comb begin
        shifted_value = remainder_quotient << 1;
        next_value    = shifted_value;

        if (shifted_value[127:64] >= denominator_reg) begin
            next_value[127:64] =
                shifted_value[127:64] - denominator_reg;
            next_value[0] = 1'b1;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            remainder_quotient <= '0;
            denominator_reg    <= '0;
            iteration          <= '0;
            busy               <= 1'b0;
            done               <= 1'b0;
            quotient           <= '0;
            divide_by_zero     <= 1'b0;
        end
        else begin
            done <= 1'b0;

            if (start && !busy) begin
                divide_by_zero <= (denominator == 64'd0);

                if (denominator == 64'd0) begin
                    quotient <= 64'd0;
                    busy     <= 1'b0;
                    done     <= 1'b1;
                end
                else begin
                    remainder_quotient <= {64'd0, numerator};
                    denominator_reg    <= denominator;
                    iteration          <= 6'd0;
                    busy               <= 1'b1;
                end
            end
            else if (busy) begin
                remainder_quotient <= next_value;

                if (iteration == 6'd63) begin
                    quotient <= next_value[63:0];
                    busy     <= 1'b0;
                    done     <= 1'b1;
                end
                else begin
                    iteration <= iteration + 1'b1;
                end
            end
        end
    end

endmodule

`default_nettype wire
