`timescale 1ns / 1ps
`default_nettype none

module tb_hall_gate_speed;

    localparam longint unsigned TB_CLK_HZ       = 1_000_000;
    localparam integer unsigned TB_FILTER_US    = 4;
    localparam integer unsigned PULSE_CYCLES    = 10;
    localparam integer unsigned INTERVAL_CYCLES = 20_000;

    logic clk_50m   = 1'b0;
    logic pl_key1_n = 1'b0;
    logic hall_a_in = 1'b1;
    logic hall_b_in = 1'b1;

    wire uart_tx;
    wire pl_led1;
    wire pl_led2;
    wire tm_clk;
    tri  tm_dio;

    logic        report_seen;
    logic [1:0]  captured_direction;
    logic [63:0] captured_speed;
    integer display_clock_edges;
    integer uart_falling_edges;

    always #500 clk_50m = ~clk_50m;
    pullup (tm_dio);

    hall_gate_speed_top #(
        .CLK_HZ           (TB_CLK_HZ),
        .POR_CYCLES       (10),
        .FILTER_US        (TB_FILTER_US),
        .HALL_ACTIVE_LOW  (1'b1),
        .DIST_FWD_MM      (100),
        .DIST_REV_MM      (100),
        .MIN_SPEED_MM_S   (100),
        .MAX_SPEED_MM_S   (10_000),
        .UART_BAUD        (100_000),
        .LED_FLASH_CYCLES (1_000)
    ) dut (
        .clk_50m   (clk_50m),
        .pl_key1_n (pl_key1_n),
        .hall_a_in (hall_a_in),
        .hall_b_in (hall_b_in),
        .uart_tx   (uart_tx),
        .pl_led1   (pl_led1),
        .pl_led2   (pl_led2),
        .tm_clk    (tm_clk),
        .tm_dio    (tm_dio)
    );

    always @(negedge tm_clk) begin
        display_clock_edges = display_clock_edges + 1;
    end

    always @(negedge uart_tx) begin
        uart_falling_edges = uart_falling_edges + 1;
    end

    always @(posedge clk_50m) begin
        if (dut.report_valid && dut.report_ready) begin
            report_seen        <= 1'b1;
            captured_direction <= dut.report_direction;
            captured_speed     <= dut.report_speed_mm_s;
        end
    end

    task automatic pulse_a;
        begin
            hall_a_in <= 1'b0;
            repeat (PULSE_CYCLES) @(negedge clk_50m);
            hall_a_in <= 1'b1;
        end
    endtask

    task automatic pulse_b;
        begin
            hall_b_in <= 1'b0;
            repeat (PULSE_CYCLES) @(negedge clk_50m);
            hall_b_in <= 1'b1;
        end
    endtask

    task automatic wait_for_report;
        integer wait_cycles;
        begin
            wait_cycles = 0;
            while (!report_seen && wait_cycles < 1_000) begin
                @(posedge clk_50m);
                wait_cycles = wait_cycles + 1;
            end
            if (!report_seen) begin
                $fatal(1, "ERROR: no speed report produced");
            end
        end
    endtask

    initial begin
        report_seen         = 1'b0;
        captured_direction  = 2'd0;
        captured_speed      = 64'd0;
        display_clock_edges = 0;
        uart_falling_edges  = 0;

        repeat (5) @(posedge clk_50m);
        @(negedge clk_50m);
        pl_key1_n <= 1'b1;

        wait (dut.rst === 1'b0);
        repeat (5) @(posedge clk_50m);

        @(negedge clk_50m);
        pulse_a();
        repeat (INTERVAL_CYCLES - PULSE_CYCLES) @(negedge clk_50m);
        pulse_b();
        wait_for_report();

        if (captured_direction !== 2'd1) begin
            $fatal(1, "ERROR: forward direction=%0d", captured_direction);
        end
        if ($isunknown(captured_speed)) begin
            $fatal(1, "ERROR: forward speed contains X");
        end
        if (captured_speed < 64'd4_900 ||
            captured_speed > 64'd5_100) begin
            $fatal(1, "ERROR: forward speed=%0d mm/s", captured_speed);
        end
        if (pl_led1 !== 1'b1) begin
            $fatal(1, "ERROR: LED1 did not light");
        end
        if (pl_led2 !== 1'b1) begin
            $fatal(1, "ERROR: LED2 should indicate forward");
        end

        $display("PASS forward: speed=%0d mm/s", captured_speed);

        report_seen = 1'b0;
        repeat (1_200) @(posedge clk_50m);

        @(negedge clk_50m);
        pulse_b();
        repeat (INTERVAL_CYCLES - PULSE_CYCLES) @(negedge clk_50m);
        pulse_a();
        wait_for_report();

        if (captured_direction !== 2'd2) begin
            $fatal(1, "ERROR: reverse direction=%0d", captured_direction);
        end
        if ($isunknown(captured_speed)) begin
            $fatal(1, "ERROR: reverse speed contains X");
        end
        if (captured_speed < 64'd4_900 ||
            captured_speed > 64'd5_100) begin
            $fatal(1, "ERROR: reverse speed=%0d mm/s", captured_speed);
        end
        if (pl_led2 !== 1'b0) begin
            $fatal(1, "ERROR: LED2 should indicate reverse");
        end
        if (display_clock_edges == 0) begin
            $fatal(1, "ERROR: TM1637 clock did not toggle");
        end
        if (uart_falling_edges == 0) begin
            $fatal(1, "ERROR: UART did not transmit");
        end

        $display("PASS reverse: speed=%0d mm/s", captured_speed);
        $display("ALL TESTS PASSED");

        repeat (20) @(posedge clk_50m);
        $finish;
    end

    initial begin
        #100_000_000;
        $fatal(1, "ERROR: simulation timeout");
    end

endmodule

`default_nettype wire
