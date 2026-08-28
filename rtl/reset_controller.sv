`timescale 1ns / 1ps
`default_nettype none

module reset_controller #(
    parameter integer unsigned POR_CYCLES = 1_000_000
) (
    input  wire  clk,
    input  wire  ext_reset_n,
    output logic rst
);

    localparam integer unsigned COUNT_WIDTH =
        (POR_CYCLES <= 1) ? 1 : $clog2(POR_CYCLES + 1);

    // KEY1 is asynchronous to the PL clock. Initial values are supported by
    // the target Xilinx FPGA and keep the design in reset after configuration.
    (* ASYNC_REG = "TRUE" *) logic [1:0] key_sync = 2'b00;

    logic [COUNT_WIDTH-1:0] por_count = '0;
    logic por_done = 1'b0;

    always_ff @(posedge clk) begin
        key_sync <= {key_sync[0], ext_reset_n};

        if (!key_sync[1]) begin
            por_count <= '0;
            por_done  <= 1'b0;
        end
        else if (!por_done) begin
            if ((POR_CYCLES <= 1) ||
                (por_count == POR_CYCLES - 1)) begin
                por_done <= 1'b1;
            end
            else begin
                por_count <= por_count + 1'b1;
            end
        end
    end

    always_comb begin
        rst = !por_done;
    end

endmodule

`default_nettype wire
