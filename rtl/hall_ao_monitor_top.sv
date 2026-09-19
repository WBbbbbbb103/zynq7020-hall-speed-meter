`timescale 1ns / 1ps
`default_nettype none

// Stage-1 dual-AO bring-up top:
// - retains digital Hall speed measurement and TM1637/LED behavior;
// - samples VAUX0/VAUX8 simultaneously at a nominal 50 kpair/s;
// - captures independent pre/post-trigger windows around Hall A and Hall B;
// - exports both completed windows over UART for plotting and fitting;
// - exposes the live signals to an ILA for bench bring-up.
module hall_ao_monitor_top #(
    parameter longint unsigned CLK_HZ           = 50_000_000,
    parameter integer unsigned POR_CYCLES       = 1_000_000,
    parameter integer unsigned FILTER_US        = 50,
    parameter bit              HALL_ACTIVE_LOW  = 1'b1,
    parameter longint unsigned DIST_FWD_MM      = 500,
    parameter longint unsigned DIST_REV_MM      = 500,
    parameter longint unsigned MIN_SPEED_MM_S   = 50,
    parameter longint unsigned MAX_SPEED_MM_S   = 5_000,
    parameter integer unsigned UART_BAUD        = 115_200,
    parameter integer unsigned LED_FLASH_CYCLES = 5_000_000,
    parameter integer unsigned CAPTURE_DEPTH    = 16_384,
    parameter integer unsigned PRE_SAMPLES      = 4_096,
    parameter longint unsigned FOUR_EDGE_TIMEOUT_CYCLES = CLK_HZ * 5
) (
    input  wire clk_50m,
    input  wire pl_key1_n,
    input  wire hall_a_in,
    input  wire hall_b_in,

    input  wire vp_in,
    input  wire vn_in,
    input  wire vauxp0,
    input  wire vauxn0,
    input  wire vauxp8,
    input  wire vauxn8,

    output wire  uart_tx,
    output wire  pl_led1,
    output logic pl_led2,
    output wire  tm_clk,
    output wire  tm_dio
);

    localparam logic [1:0] DIR_FWD = 2'd1;
    localparam integer unsigned LED_COUNTER_WIDTH =
        (LED_FLASH_CYCLES < 2) ? 1 : $clog2(LED_FLASH_CYCLES + 1);
    localparam integer unsigned CAPTURE_ADDR_WIDTH =
        (CAPTURE_DEPTH <= 2) ? 1 : $clog2(CAPTURE_DEPTH);
    localparam logic [LED_COUNTER_WIDTH-1:0] LED_FLASH_LOAD =
        LED_FLASH_CYCLES;

    wire rst;
    wire hall_a_active;
    wire hall_b_active;
    wire hall_a_event;
    wire hall_b_event;
    wire report_valid;
    wire report_ready;
    wire [1:0] report_direction;
    wire [63:0] report_speed_mm_s;
    wire [63:0] last_interval_ticks;
    wire [13:0] display_speed;
    logic [LED_COUNTER_WIDTH-1:0] led_flash_count;

    wire [11:0] adc_a;
    wire [11:0] adc_b;
    wire        adc_valid;
    wire        xadc_busy;
    wire [7:0]  uart_data;
    wire        uart_data_valid;
    wire        uart_data_ready;
    wire        capture_a_active;
    wire        capture_b_active;
    wire        capture_a_done;
    wire        capture_b_done;
    wire        capture_a_rd_en;
    wire        capture_b_rd_en;
    wire [CAPTURE_ADDR_WIDTH-1:0] capture_rd_index;
    wire [23:0] capture_a_rd_data;
    wire [23:0] capture_b_rd_data;
    wire        export_busy;
    wire        export_done;
    logic       reset_was_active;
    wire        four_edge_arm;
    wire        four_edge_busy;
    wire        four_edge_done;
    wire        four_edge_error;
    wire [1:0]  four_edge_error_code;
    wire [3:0]  four_edge_seen;
    wire [63:0] t_a_on;
    wire [63:0] t_a_off;
    wire [63:0] t_b_on;
    wire [63:0] t_b_off;

    reset_controller #(
        .POR_CYCLES(POR_CYCLES)
    ) u_reset_controller (
        .clk         (clk_50m),
        .ext_reset_n (pl_key1_n),
        .rst         (rst)
    );

    hall_input_filter #(
        .CLK_HZ     (CLK_HZ),
        .FILTER_US  (FILTER_US),
        .ACTIVE_LOW (HALL_ACTIVE_LOW)
    ) u_hall_a_filter (
        .clk         (clk_50m),
        .rst         (rst),
        .hall_async  (hall_a_in),
        .hall_active (hall_a_active),
        .event_pulse (hall_a_event)
    );

    hall_input_filter #(
        .CLK_HZ     (CLK_HZ),
        .FILTER_US  (FILTER_US),
        .ACTIVE_LOW (HALL_ACTIVE_LOW)
    ) u_hall_b_filter (
        .clk         (clk_50m),
        .rst         (rst),
        .hall_async  (hall_b_in),
        .hall_active (hall_b_active),
        .event_pulse (hall_b_event)
    );

    always_ff @(posedge clk_50m) begin
        if (rst)
            reset_was_active <= 1'b1;
        else
            reset_was_active <= 1'b0;
    end

    assign four_edge_arm = reset_was_active && !rst;

    hall_four_edge_capture #(
        .TIMEOUT_CYCLES(FOUR_EDGE_TIMEOUT_CYCLES)
    ) u_hall_four_edge_capture (
        .clk           (clk_50m),
        .rst           (rst),
        .arm           (four_edge_arm),
        .hall_a_active (hall_a_active),
        .hall_b_active (hall_b_active),
        .busy          (four_edge_busy),
        .done          (four_edge_done),
        .error         (four_edge_error),
        .error_code    (four_edge_error_code),
        .seen_edges    (four_edge_seen),
        .t_a_on        (t_a_on),
        .t_a_off       (t_a_off),
        .t_b_on        (t_b_on),
        .t_b_off       (t_b_off)
    );

    hall_gate_measure #(
        .CLK_HZ         (CLK_HZ),
        .DIST_FWD_MM    (DIST_FWD_MM),
        .DIST_REV_MM    (DIST_REV_MM),
        .MIN_SPEED_MM_S (MIN_SPEED_MM_S),
        .MAX_SPEED_MM_S (MAX_SPEED_MM_S)
    ) u_hall_gate_measure (
        .clk                 (clk_50m),
        .rst                 (rst),
        .hall_a_event        (hall_a_event),
        .hall_b_event        (hall_b_event),
        .report_ready        (report_ready),
        .report_valid        (report_valid),
        .report_direction    (report_direction),
        .report_speed_mm_s   (report_speed_mm_s),
        .last_interval_ticks (last_interval_ticks)
    );

    // The stage-1 UART is reserved for ADC monitoring. Consume digital speed
    // reports immediately; speed remains visible on TM1637 and LEDs.
    assign report_ready = 1'b1;

    xadc_dual_reader #(
        .DECIMATION(10)
    ) u_xadc_dual_reader (
        .clk          (clk_50m),
        .rst          (rst),
        .vp_in        (vp_in),
        .vn_in        (vn_in),
        .vauxp0       (vauxp0),
        .vauxn0       (vauxn0),
        .vauxp8       (vauxp8),
        .vauxn8       (vauxn8),
        .sample_a     (adc_a),
        .sample_b     (adc_b),
        .sample_valid (adc_valid),
        .xadc_busy    (xadc_busy)
    );

    event_capture_buffer #(
        .DEPTH       (CAPTURE_DEPTH),
        .PRE_SAMPLES (PRE_SAMPLES)
    ) u_capture_a (
        .clk            (clk_50m),
        .rst            (rst),
        .sample_valid   (adc_valid),
        .sample_a       (adc_a),
        .sample_b       (adc_b),
        .trigger        (hall_a_event),
        .capture_active (capture_a_active),
        .capture_done   (capture_a_done),
        .rd_en          (capture_a_rd_en),
        .rd_index       (capture_rd_index),
        .rd_data        (capture_a_rd_data)
    );

    event_capture_buffer #(
        .DEPTH       (CAPTURE_DEPTH),
        .PRE_SAMPLES (PRE_SAMPLES)
    ) u_capture_b (
        .clk            (clk_50m),
        .rst            (rst),
        .sample_valid   (adc_valid),
        .sample_a       (adc_a),
        .sample_b       (adc_b),
        .trigger        (hall_b_event),
        .capture_active (capture_b_active),
        .capture_done   (capture_b_done),
        .rd_en          (capture_b_rd_en),
        .rd_index       (capture_rd_index),
        .rd_data        (capture_b_rd_data)
    );

    ao_capture_uart_exporter #(
        .DEPTH(CAPTURE_DEPTH)
    ) u_ao_capture_uart_exporter (
        .clk               (clk_50m),
        .rst               (rst),
        .capture_a_done    (capture_a_done),
        .capture_b_done    (capture_b_done),
        .edge_capture_done (four_edge_done),
        .edge_capture_error(four_edge_error),
        .edge_error_code   (four_edge_error_code),
        .edge_seen         (four_edge_seen),
        .t_a_on            (t_a_on),
        .t_a_off           (t_a_off),
        .t_b_on            (t_b_on),
        .t_b_off           (t_b_off),
        .capture_a_rd_en   (capture_a_rd_en),
        .capture_b_rd_en   (capture_b_rd_en),
        .capture_rd_index  (capture_rd_index),
        .capture_a_rd_data (capture_a_rd_data),
        .capture_b_rd_data (capture_b_rd_data),
        .tx_ready          (uart_data_ready),
        .tx_data           (uart_data),
        .tx_valid          (uart_data_valid),
        .export_busy       (export_busy),
        .export_done       (export_done)
    );

    uart_tx_8n1 #(
        .CLK_HZ (CLK_HZ),
        .BAUD   (UART_BAUD)
    ) u_uart_tx (
        .clk   (clk_50m),
        .rst   (rst),
        .data  (uart_data),
        .valid (uart_data_valid),
        .ready (uart_data_ready),
        .tx    (uart_tx)
    );

    ila_ao_debug u_ila_ao_debug (
        .clk    (clk_50m),
        .probe0 (adc_a),
        .probe1 (adc_b),
        .probe2 (adc_valid),
        .probe3 (hall_a_active),
        .probe4 (hall_b_active),
        .probe5 (hall_a_event),
        .probe6 (hall_b_event),
        .probe7 (capture_a_done),
        .probe8 (capture_b_done)
    );

    assign display_speed =
        (report_speed_mm_s > 64'd9999)
        ? 14'd9999
        : report_speed_mm_s[13:0];

    tm1637_display #(
        .CLK_HZ  (CLK_HZ),
        .STEP_HZ (10_000)
    ) u_tm1637_display (
        .clk    (clk_50m),
        .rst    (rst),
        .value  (display_speed),
        .tm_clk (tm_clk),
        .tm_dio (tm_dio)
    );

    always_ff @(posedge clk_50m) begin
        if (rst) begin
            led_flash_count <= '0;
            pl_led2         <= 1'b0;
        end
        else if (report_valid && report_ready) begin
            led_flash_count <= LED_FLASH_LOAD;
            pl_led2         <= (report_direction == DIR_FWD);
        end
        else if (led_flash_count != '0) begin
            led_flash_count <= led_flash_count - 1'b1;
        end
    end

    assign pl_led1 = (led_flash_count != '0);

endmodule

`default_nettype wire
