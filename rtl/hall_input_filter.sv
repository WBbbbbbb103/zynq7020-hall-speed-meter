`timescale 1ns / 1ps
`default_nettype none

module hall_input_filter #(
    parameter integer unsigned CLK_HZ     = 50_000_000,
    parameter integer unsigned FILTER_US  = 50,
    parameter bit              ACTIVE_LOW = 1'b1
) (
    input  wire  clk,
    input  wire  rst,
    input  wire  hall_async,
    output logic hall_active,
    output logic event_pulse
);

    localparam integer unsigned FILTER_CYCLES_RAW =
        (CLK_HZ / 1_000_000) * FILTER_US;

    localparam integer unsigned FILTER_CYCLES =
        (FILTER_CYCLES_RAW < 2) ? 2 : FILTER_CYCLES_RAW;

    localparam integer unsigned COUNT_WIDTH =
        (FILTER_CYCLES <= 1) ? 1 : $clog2(FILTER_CYCLES);

    localparam logic IDLE_LEVEL =
        ACTIVE_LOW ? 1'b1 : 1'b0;

    localparam logic ACTIVE_LEVEL =
        ACTIVE_LOW ? 1'b0 : 1'b1;

    // Two-stage synchronizer for each asynchronous Hall input.
    (* ASYNC_REG = "TRUE" *) logic sync_ff1;
    (* ASYNC_REG = "TRUE" *) logic sync_ff2;

    logic filtered_level;
    logic [COUNT_WIDTH-1:0] stable_count;

    always_ff @(posedge clk) begin
        if (rst) begin
            sync_ff1       <= IDLE_LEVEL;
            sync_ff2       <= IDLE_LEVEL;
            filtered_level <= IDLE_LEVEL;
            stable_count   <= '0;
            event_pulse    <= 1'b0;
        end
        else begin
            sync_ff1    <= hall_async;
            sync_ff2    <= sync_ff1;
            event_pulse <= 1'b0;

            if (sync_ff2 == filtered_level) begin
                stable_count <= '0;
            end
            else if (stable_count == FILTER_CYCLES - 1) begin
                filtered_level <= sync_ff2;
                stable_count   <= '0;

                if (sync_ff2 == ACTIVE_LEVEL) begin
                    event_pulse <= 1'b1;
                end
            end
            else begin
                stable_count <= stable_count + 1'b1;
            end
        end
    end

    always_comb begin
        hall_active = (filtered_level == ACTIVE_LEVEL);
    end

endmodule

`default_nettype wire
