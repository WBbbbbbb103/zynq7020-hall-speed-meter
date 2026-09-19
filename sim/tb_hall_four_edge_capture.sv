`timescale 1ns / 1ps
`default_nettype none

module tb_hall_four_edge_capture;

    logic clk = 1'b0;
    logic rst = 1'b1;
    logic arm = 1'b0;
    logic hall_a_active = 1'b0;
    logic hall_b_active = 1'b0;

    wire busy;
    wire done;
    wire error;
    wire [1:0] error_code;
    wire [3:0] seen_edges;
    wire [63:0] t_a_on;
    wire [63:0] t_a_off;
    wire [63:0] t_b_on;
    wire [63:0] t_b_off;

    always #10 clk = ~clk;

    hall_four_edge_capture #(
        .TIMEOUT_CYCLES(40)
    ) u_dut (
        .clk(clk),
        .rst(rst),
        .arm(arm),
        .hall_a_active(hall_a_active),
        .hall_b_active(hall_b_active),
        .busy(busy),
        .done(done),
        .error(error),
        .error_code(error_code),
        .seen_edges(seen_edges),
        .t_a_on(t_a_on),
        .t_a_off(t_a_off),
        .t_b_on(t_b_on),
        .t_b_off(t_b_off)
    );

    task automatic pulse_arm;
        begin
            @(negedge clk);
            arm = 1'b1;
            @(negedge clk);
            arm = 1'b0;
        end
    endtask

    task automatic expect_success;
        begin
            wait (done);
            @(posedge clk);
            if (error || error_code != 2'd0 || seen_edges != 4'hF)
                $fatal(1, "Expected success: error=%0b code=%0d seen=%h",
                       error, error_code, seen_edges);
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        rst = 1'b0;

        // Forward pass: A_ON, B_ON, A_OFF, B_OFF.
        pulse_arm();
        @(negedge clk);
        hall_a_active = 1'b1;
        repeat (7) @(negedge clk);
        hall_b_active = 1'b1;
        repeat (3) @(negedge clk);
        hall_a_active = 1'b0;
        repeat (9) @(negedge clk);
        hall_b_active = 1'b0;
        expect_success();

        if ((t_b_on - t_a_on) != 64'd7 ||
            (t_a_off - t_b_on) != 64'd3 ||
            (t_b_off - t_a_off) != 64'd9)
            $fatal(1, "Forward timestamp differences were %0d, %0d, %0d",
                   t_b_on - t_a_on,
                   t_a_off - t_b_on,
                   t_b_off - t_a_off);

        // Reverse pass: B_ON, A_ON, B_OFF, A_OFF.
        repeat (2) @(posedge clk);
        pulse_arm();
        @(negedge clk);
        hall_b_active = 1'b1;
        repeat (5) @(negedge clk);
        hall_a_active = 1'b1;
        repeat (4) @(negedge clk);
        hall_b_active = 1'b0;
        repeat (6) @(negedge clk);
        hall_a_active = 1'b0;
        expect_success();

        if ((t_a_on - t_b_on) != 64'd5 ||
            (t_b_off - t_a_on) != 64'd4 ||
            (t_a_off - t_b_off) != 64'd6)
            $fatal(1, "Reverse timestamp differences were %0d, %0d, %0d",
                   t_a_on - t_b_on,
                   t_b_off - t_a_on,
                   t_a_off - t_b_off);

        // Arming while a Hall input is already active must fail safely.
        repeat (2) @(posedge clk);
        hall_a_active = 1'b1;
        pulse_arm();
        @(posedge clk);
        if (!done || !error || error_code != 2'd1 || busy)
            $fatal(1, "Active-at-arm check failed");

        // No edges after arming must terminate with a timeout error.
        hall_a_active = 1'b0;
        repeat (2) @(posedge clk);
        pulse_arm();
        wait (done);
        @(posedge clk);
        if (!error || error_code != 2'd3 || busy)
            $fatal(1, "Timeout check failed");

        $display("HALL FOUR EDGE CAPTURE TEST PASSED");
        $finish;
    end

    initial begin
        #100_000;
        $fatal(1, "Simulation timeout");
    end

endmodule

`default_nettype wire
