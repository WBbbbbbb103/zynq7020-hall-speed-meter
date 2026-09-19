`timescale 1ns / 1ps
`default_nettype none

// Captures one ON edge and one OFF edge from each filtered Hall input.
// Timestamps use the FPGA clock and remain valid until the next arm pulse.
module hall_four_edge_capture #(
    parameter longint unsigned TIMEOUT_CYCLES = 100_000_000
) (
    input  wire         clk,
    input  wire         rst,
    input  wire         arm,
    input  wire         hall_a_active,
    input  wire         hall_b_active,

    output logic        busy,
    output logic        done,
    output logic        error,
    output logic [1:0]  error_code,
    output logic [3:0]  seen_edges,
    output logic [63:0] t_a_on,
    output logic [63:0] t_a_off,
    output logic [63:0] t_b_on,
    output logic [63:0] t_b_off
);

    localparam integer unsigned TIMEOUT_WIDTH =
        (TIMEOUT_CYCLES < 2) ? 1 : $clog2(TIMEOUT_CYCLES);
    localparam logic [TIMEOUT_WIDTH-1:0] TIMEOUT_LIMIT =
        TIMEOUT_CYCLES - 1;

    logic [63:0] timestamp_counter;
    logic [TIMEOUT_WIDTH-1:0] timeout_counter;
    logic hall_a_previous;
    logic hall_b_previous;

    wire a_on_edge  = busy &&  hall_a_active && !hall_a_previous;
    wire a_off_edge = busy && !hall_a_active &&  hall_a_previous;
    wire b_on_edge  = busy &&  hall_b_active && !hall_b_previous;
    wire b_off_edge = busy && !hall_b_active &&  hall_b_previous;

    wire [3:0] new_edges = {
        b_off_edge && !seen_edges[3],
        b_on_edge  && !seen_edges[2],
        a_off_edge && !seen_edges[1],
        a_on_edge  && !seen_edges[0]
    };

    always_ff @(posedge clk) begin
        if (rst) begin
            timestamp_counter <= 64'd0;
            timeout_counter   <= '0;
            hall_a_previous   <= 1'b0;
            hall_b_previous   <= 1'b0;
            busy              <= 1'b0;
            done              <= 1'b0;
            error             <= 1'b0;
            error_code        <= 2'd0;
            seen_edges        <= 4'd0;
            t_a_on            <= 64'd0;
            t_a_off           <= 64'd0;
            t_b_on            <= 64'd0;
            t_b_off           <= 64'd0;
        end
        else begin
            timestamp_counter <= timestamp_counter + 1'b1;
            hall_a_previous   <= hall_a_active;
            hall_b_previous   <= hall_b_active;

            if (arm) begin
                timeout_counter <= '0;
                done            <= 1'b0;
                error           <= hall_a_active || hall_b_active;
                error_code      <= (hall_a_active || hall_b_active) ? 2'd1 : 2'd0;
                busy            <= !(hall_a_active || hall_b_active);
                seen_edges      <= 4'd0;
                t_a_on          <= 64'd0;
                t_a_off         <= 64'd0;
                t_b_on          <= 64'd0;
                t_b_off         <= 64'd0;
                if (hall_a_active || hall_b_active)
                    done <= 1'b1;
            end
            else if (busy) begin
                if ((a_off_edge && !seen_edges[0]) ||
                    (b_off_edge && !seen_edges[2])) begin
                    busy       <= 1'b0;
                    done       <= 1'b1;
                    error      <= 1'b1;
                    error_code <= 2'd2;
                end
                else if (timeout_counter == TIMEOUT_LIMIT) begin
                    busy       <= 1'b0;
                    done       <= 1'b1;
                    error      <= 1'b1;
                    error_code <= 2'd3;
                end
                else begin
                    timeout_counter <= timeout_counter + 1'b1;
                    seen_edges      <= seen_edges | new_edges;

                    if (new_edges[0])
                        t_a_on <= timestamp_counter;
                    if (new_edges[1])
                        t_a_off <= timestamp_counter;
                    if (new_edges[2])
                        t_b_on <= timestamp_counter;
                    if (new_edges[3])
                        t_b_off <= timestamp_counter;

                    if ((seen_edges | new_edges) == 4'hF) begin
                        busy <= 1'b0;
                        done <= 1'b1;
                    end
                end
            end
        end
    end

endmodule

`default_nettype wire
