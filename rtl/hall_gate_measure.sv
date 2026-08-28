`timescale 1ns / 1ps
`default_nettype none

module hall_gate_measure #(
    parameter longint unsigned CLK_HZ         = 50_000_000,
    parameter longint unsigned DIST_FWD_MM    = 500,
    parameter longint unsigned DIST_REV_MM    = 500,
    parameter longint unsigned MIN_SPEED_MM_S = 50,
    parameter longint unsigned MAX_SPEED_MM_S = 5_000
) (
    input  wire         clk,
    input  wire         rst,
    input  wire         hall_a_event,
    input  wire         hall_b_event,
    input  wire         report_ready,

    output logic        report_valid,
    output logic [1:0]  report_direction,
    output logic [63:0] report_speed_mm_s,
    output logic [63:0] last_interval_ticks
);

    localparam logic [1:0] DIR_FWD = 2'd1;
    localparam logic [1:0] DIR_REV = 2'd2;

    localparam longint unsigned MAX_DISTANCE_MM =
        (DIST_FWD_MM > DIST_REV_MM) ? DIST_FWD_MM : DIST_REV_MM;

    // Abort an incomplete measurement after the minimum-speed interval plus
    // one second of margin.
    localparam longint unsigned TIMEOUT_TICKS =
        ((MAX_DISTANCE_MM * CLK_HZ) / MIN_SPEED_MM_S) + CLK_HZ;

    typedef enum logic [2:0] {
        STATE_IDLE,
        STATE_WAIT_B,
        STATE_WAIT_A,
        STATE_WAIT_DIV,
        STATE_REPORT
    } state_t;

    state_t state;

    logic [63:0] timestamp;
    logic [63:0] start_timestamp;
    logic [1:0]  pending_direction;

    logic        div_start;
    logic        div_done;
    logic        div_zero;
    logic [63:0] div_numerator;
    logic [63:0] div_denominator;
    logic [63:0] div_quotient;

    udiv64 u_divider (
        .clk            (clk),
        .rst            (rst),
        .start          (div_start),
        .numerator      (div_numerator),
        .denominator    (div_denominator),
        .busy           (),
        .done           (div_done),
        .quotient       (div_quotient),
        .divide_by_zero (div_zero)
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            state               <= STATE_IDLE;
            timestamp           <= 64'd0;
            start_timestamp     <= 64'd0;
            pending_direction   <= 2'd0;
            div_start           <= 1'b0;
            div_numerator       <= 64'd0;
            div_denominator     <= 64'd0;
            report_valid        <= 1'b0;
            report_direction    <= 2'd0;
            report_speed_mm_s   <= 64'd0;
            last_interval_ticks <= 64'd0;
        end
        else begin
            timestamp <= timestamp + 1'b1;
            div_start <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    report_valid <= 1'b0;

                    if (hall_a_event && !hall_b_event) begin
                        start_timestamp <= timestamp;
                        state           <= STATE_WAIT_B;
                    end
                    else if (hall_b_event && !hall_a_event) begin
                        start_timestamp <= timestamp;
                        state           <= STATE_WAIT_A;
                    end
                end

                STATE_WAIT_B: begin
                    if ((timestamp - start_timestamp) > TIMEOUT_TICKS) begin
                        state <= STATE_IDLE;
                    end
                    else if (hall_b_event) begin
                        last_interval_ticks <= timestamp - start_timestamp;
                        div_numerator       <= DIST_FWD_MM * CLK_HZ;
                        div_denominator     <= timestamp - start_timestamp;
                        pending_direction   <= DIR_FWD;
                        div_start           <= 1'b1;
                        state               <= STATE_WAIT_DIV;
                    end
                end

                STATE_WAIT_A: begin
                    if ((timestamp - start_timestamp) > TIMEOUT_TICKS) begin
                        state <= STATE_IDLE;
                    end
                    else if (hall_a_event) begin
                        last_interval_ticks <= timestamp - start_timestamp;
                        div_numerator       <= DIST_REV_MM * CLK_HZ;
                        div_denominator     <= timestamp - start_timestamp;
                        pending_direction   <= DIR_REV;
                        div_start           <= 1'b1;
                        state               <= STATE_WAIT_DIV;
                    end
                end

                STATE_WAIT_DIV: begin
                    if (div_done) begin
                        if (!div_zero &&
                            (div_quotient >= MIN_SPEED_MM_S) &&
                            (div_quotient <= MAX_SPEED_MM_S)) begin
                            report_direction  <= pending_direction;
                            report_speed_mm_s <= div_quotient;
                            report_valid      <= 1'b1;
                            state             <= STATE_REPORT;
                        end
                        else begin
                            state <= STATE_IDLE;
                        end
                    end
                end

                STATE_REPORT: begin
                    if (report_valid && report_ready) begin
                        report_valid <= 1'b0;
                        state        <= STATE_IDLE;
                    end
                end

                default: begin
                    state <= STATE_IDLE;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
