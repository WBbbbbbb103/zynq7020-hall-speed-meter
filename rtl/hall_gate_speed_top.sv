`timescale 1ns / 1ps
`default_nettype none

module hall_gate_speed_top #(
    parameter longint unsigned CLK_HZ           = 50_000_000,
    parameter integer unsigned POR_CYCLES       = 1_000_000,

    // DIST_FWD_MM and DIST_REV_MM are placeholders until the physical gates
    // have been calibrated in both directions.
    parameter integer unsigned FILTER_US        = 50,
    parameter bit              HALL_ACTIVE_LOW  = 1'b1,
    parameter longint unsigned DIST_FWD_MM      = 500,
    parameter longint unsigned DIST_REV_MM      = 500,
    parameter longint unsigned MIN_SPEED_MM_S   = 50,
    parameter longint unsigned MAX_SPEED_MM_S   = 5_000,

    parameter integer unsigned UART_BAUD        = 115_200,
    parameter integer unsigned LED_FLASH_CYCLES = 5_000_000
) (
    input  wire clk_50m,
    input  wire pl_key1_n,
    input  wire hall_a_in,
    input  wire hall_b_in,

    output wire  uart_tx,
    output wire  pl_led1,
    output logic pl_led2,
    output wire  tm_clk,
    output wire  tm_dio
);

    localparam logic [1:0] DIR_FWD = 2'd1;

    localparam integer unsigned LED_COUNTER_WIDTH =
        (LED_FLASH_CYCLES < 2) ? 1 : $clog2(LED_FLASH_CYCLES + 1);

    localparam logic [LED_COUNTER_WIDTH-1:0] LED_FLASH_LOAD =
        LED_FLASH_CYCLES;

    wire rst;
    wire hall_a_active;
    wire hall_b_active;
    wire hall_a_event;
    wire hall_b_event;
    wire        report_valid;
    wire        report_ready;
    wire [1:0]  report_direction;
    wire [63:0] report_speed_mm_s;
    wire [63:0] last_interval_ticks;
    wire [7:0]  uart_data;
    wire        uart_data_valid;
    wire        uart_data_ready;
    wire [13:0] display_speed;
    logic [LED_COUNTER_WIDTH-1:0] led_flash_count;

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

    uart_reporter u_uart_reporter (
        .clk               (clk_50m),
        .rst               (rst),
        .report_valid      (report_valid),
        .report_ready      (report_ready),
        .report_direction  (report_direction),
        .report_speed_mm_s (report_speed_mm_s),
        .tx_data           (uart_data),
        .tx_valid          (uart_data_valid),
        .tx_ready          (uart_data_ready)
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
