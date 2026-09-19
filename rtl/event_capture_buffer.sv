`timescale 1ns / 1ps
`default_nettype none

// One-shot circular capture buffer with samples from before and after an event.
// DEPTH must be a power of two. The memory is inferred as simple dual-port BRAM:
// one port records samples and the other exports a completed capture.
module event_capture_buffer #(
    parameter integer unsigned DEPTH       = 16_384,
    parameter integer unsigned PRE_SAMPLES = 4_096,
    parameter integer unsigned ADDR_WIDTH  =
        (DEPTH <= 2) ? 1 : $clog2(DEPTH)
) (
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  sample_valid,
    input  wire [11:0]           sample_a,
    input  wire [11:0]           sample_b,
    input  wire                  trigger,

    output logic                 capture_active,
    output logic                 capture_done,

    input  wire                  rd_en,
    input  wire [ADDR_WIDTH-1:0] rd_index,
    output logic [23:0]          rd_data
);

    localparam integer unsigned POST_SAMPLES =
        DEPTH - PRE_SAMPLES - 1;
    localparam integer unsigned POST_COUNT_WIDTH =
        (POST_SAMPLES <= 1) ? 1 : $clog2(POST_SAMPLES + 1);
    localparam logic [ADDR_WIDTH-1:0] PRE_OFFSET = PRE_SAMPLES;

    (* ram_style = "block" *) logic [23:0] sample_memory [0:DEPTH-1];

    logic [ADDR_WIDTH-1:0] write_pointer;
    logic [ADDR_WIDTH-1:0] start_pointer;
    logic [POST_COUNT_WIDTH-1:0] post_remaining;
    logic trigger_pending;

    // Recording port. Before the trigger this continuously overwrites the
    // oldest sample. After the trigger it records the fixed post-event tail.
    always_ff @(posedge clk) begin
        if (rst) begin
            write_pointer  <= '0;
            start_pointer  <= '0;
            post_remaining <= '0;
            trigger_pending <= 1'b0;
            capture_active <= 1'b0;
            capture_done   <= 1'b0;
        end
        else begin
            if (trigger && !capture_active && !capture_done)
                trigger_pending <= 1'b1;

            if (sample_valid && !capture_done) begin
                sample_memory[write_pointer] <= {sample_a, sample_b};
                write_pointer <= write_pointer + 1'b1;

                if (!capture_active) begin
                    if (trigger_pending || trigger) begin
                        // write_pointer is the address of the trigger sample.
                        start_pointer   <= write_pointer - PRE_OFFSET;
                        post_remaining  <= POST_SAMPLES;
                        trigger_pending <= 1'b0;
                        capture_active  <= 1'b1;
                    end
                end
                else if (post_remaining == 1) begin
                    post_remaining <= '0;
                    capture_active <= 1'b0;
                    capture_done   <= 1'b1;
                end
                else begin
                    post_remaining <= post_remaining - 1'b1;
                end
            end
        end
    end

    // Export port. rd_index zero always refers to the oldest pre-trigger
    // sample, regardless of where the circular write pointer wrapped.
    always_ff @(posedge clk) begin
        if (rd_en)
            rd_data <= sample_memory[start_pointer + rd_index];
    end

endmodule

`default_nettype wire
