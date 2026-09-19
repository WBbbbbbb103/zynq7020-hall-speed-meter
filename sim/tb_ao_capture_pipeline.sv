`timescale 1ns / 1ps
`default_nettype none

module tb_ao_capture_pipeline;

    localparam integer DEPTH = 16;
    localparam integer PRE_SAMPLES = 4;
    localparam integer ADDR_WIDTH = 4;
    localparam integer DIGITAL_BYTES = 11 + (4 * 24);
    localparam integer EXPECTED_BYTES = 9 + DIGITAL_BYTES + (2 * DEPTH * 16) + 6;
    localparam integer EVENT_A_OFFSET = 9 + DIGITAL_BYTES;
    localparam integer EVENT_B_OFFSET = EVENT_A_OFFSET + (DEPTH * 16);

    logic clk = 1'b0;
    logic rst = 1'b1;
    logic sample_valid = 1'b0;
    logic [11:0] sample_a = '0;
    logic [11:0] sample_b = '0;
    logic trigger_a = 1'b0;
    logic trigger_b = 1'b0;

    wire capture_a_active;
    wire capture_b_active;
    wire capture_a_done;
    wire capture_b_done;
    wire capture_a_rd_en;
    wire capture_b_rd_en;
    wire [ADDR_WIDTH-1:0] capture_rd_index;
    wire [23:0] capture_a_rd_data;
    wire [23:0] capture_b_rd_data;
    wire [7:0] tx_data;
    wire tx_valid;
    wire export_busy;
    wire export_done;

    logic [7:0] transmitted [0:1023];
    integer transmitted_count = 0;
    integer sample_number;

    always #10 clk = ~clk;

    event_capture_buffer #(
        .DEPTH(DEPTH),
        .PRE_SAMPLES(PRE_SAMPLES)
    ) u_capture_a (
        .clk(clk),
        .rst(rst),
        .sample_valid(sample_valid),
        .sample_a(sample_a),
        .sample_b(sample_b),
        .trigger(trigger_a),
        .capture_active(capture_a_active),
        .capture_done(capture_a_done),
        .rd_en(capture_a_rd_en),
        .rd_index(capture_rd_index),
        .rd_data(capture_a_rd_data)
    );

    event_capture_buffer #(
        .DEPTH(DEPTH),
        .PRE_SAMPLES(PRE_SAMPLES)
    ) u_capture_b (
        .clk(clk),
        .rst(rst),
        .sample_valid(sample_valid),
        .sample_a(sample_a),
        .sample_b(sample_b),
        .trigger(trigger_b),
        .capture_active(capture_b_active),
        .capture_done(capture_b_done),
        .rd_en(capture_b_rd_en),
        .rd_index(capture_rd_index),
        .rd_data(capture_b_rd_data)
    );

    ao_capture_uart_exporter #(
        .DEPTH(DEPTH)
    ) u_exporter (
        .clk(clk),
        .rst(rst),
        .capture_a_done(capture_a_done),
        .capture_b_done(capture_b_done),
        .edge_capture_done(1'b1),
        .edge_capture_error(1'b0),
        .edge_error_code(2'd0),
        .edge_seen(4'hF),
        .t_a_on(64'h0000_0000_0000_0010),
        .t_a_off(64'h0000_0000_0000_0020),
        .t_b_on(64'h0000_0000_0000_0030),
        .t_b_off(64'h0000_0000_0000_0040),
        .capture_a_rd_en(capture_a_rd_en),
        .capture_b_rd_en(capture_b_rd_en),
        .capture_rd_index(capture_rd_index),
        .capture_a_rd_data(capture_a_rd_data),
        .capture_b_rd_data(capture_b_rd_data),
        .tx_ready(1'b1),
        .tx_data(tx_data),
        .tx_valid(tx_valid),
        .export_busy(export_busy),
        .export_done(export_done)
    );

    always_ff @(posedge clk) begin
        if (tx_valid) begin
            transmitted[transmitted_count] <= tx_data;
            transmitted_count <= transmitted_count + 1;
        end
    end

    task automatic send_sample(input integer value);
        begin
            @(negedge clk);
            sample_a = value[11:0];
            sample_b = (1000 + value);
            sample_valid = 1'b1;
            trigger_a = (value == 6);
            trigger_b = (value == 10);
            @(negedge clk);
            sample_valid = 1'b0;
            trigger_a = 1'b0;
            trigger_b = 1'b0;
        end
    endtask

    task automatic expect_byte(
        input integer position,
        input logic [7:0] expected
    );
        begin
            if (transmitted[position] !== expected)
                $fatal(1, "Byte %0d was 0x%02h, expected 0x%02h",
                       position, transmitted[position], expected);
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        rst = 1'b0;

        for (sample_number = 0; sample_number <= 25; sample_number++)
            send_sample(sample_number);

        wait (export_done);
        repeat (2) @(posedge clk);

        if (transmitted_count != EXPECTED_BYTES)
            $fatal(1, "Export length was %0d, expected %0d",
                   transmitted_count, EXPECTED_BYTES);

        // Header: #CAR2AO\r\n
        expect_byte(0, "#");
        expect_byte(1, "C");
        expect_byte(2, "A");
        expect_byte(3, "R");
        expect_byte(4, "2");
        expect_byte(5, "A");
        expect_byte(6, "O");
        expect_byte(7, 8'h0D);
        expect_byte(8, 8'h0A);

        // Digital status and first timestamp line.
        // D,STS,0,F\r\n
        expect_byte(9,  "D");
        expect_byte(11, "S");
        expect_byte(15, "0");
        expect_byte(17, "F");
        // D,AON,0000000000000010\r\n
        expect_byte(20, "D");
        expect_byte(22, "A");
        expect_byte(23, "O");
        expect_byte(24, "N");
        expect_byte(40, "1");
        expect_byte(41, "0");

        // Event A starts four samples before trigger sample 6: sample 2.
        // First line: A,0000,002,3EA\r\n
        expect_byte(EVENT_A_OFFSET + 0,  "A");
        expect_byte(EVENT_A_OFFSET + 1,  ",");
        expect_byte(EVENT_A_OFFSET + 2,  "0");
        expect_byte(EVENT_A_OFFSET + 3,  "0");
        expect_byte(EVENT_A_OFFSET + 4,  "0");
        expect_byte(EVENT_A_OFFSET + 5,  "0");
        expect_byte(EVENT_A_OFFSET + 6,  ",");
        expect_byte(EVENT_A_OFFSET + 7,  "0");
        expect_byte(EVENT_A_OFFSET + 8,  "0");
        expect_byte(EVENT_A_OFFSET + 9,  "2");
        expect_byte(EVENT_A_OFFSET + 10, ",");
        expect_byte(EVENT_A_OFFSET + 11, "3");
        expect_byte(EVENT_A_OFFSET + 12, "E");
        expect_byte(EVENT_A_OFFSET + 13, "A");

        // Event B starts four samples before trigger sample 10: sample 6.
        // Its first line begins after all 16 Event-A records.
        expect_byte(EVENT_B_OFFSET + 0, "B");
        expect_byte(EVENT_B_OFFSET + 7, "0");
        expect_byte(EVENT_B_OFFSET + 8, "0");
        expect_byte(EVENT_B_OFFSET + 9, "6");
        expect_byte(EVENT_B_OFFSET + 11, "3");
        expect_byte(EVENT_B_OFFSET + 12, "E");
        expect_byte(EVENT_B_OFFSET + 13, "E");

        expect_byte(EXPECTED_BYTES - 6, "#");
        expect_byte(EXPECTED_BYTES - 5, "E");
        expect_byte(EXPECTED_BYTES - 4, "N");
        expect_byte(EXPECTED_BYTES - 3, "D");
        expect_byte(EXPECTED_BYTES - 2, 8'h0D);
        expect_byte(EXPECTED_BYTES - 1, 8'h0A);

        $display("AO CAPTURE PIPELINE TEST PASSED");
        $finish;
    end

    initial begin
        #2_000_000;
        $fatal(1, "Simulation timeout");
    end

endmodule

`default_nettype wire
