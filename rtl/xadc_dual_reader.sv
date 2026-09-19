`timescale 1ns / 1ps
`default_nettype none

// Reads the simultaneously sampled VAUX0/VAUX8 result registers from the
// XADC Wizard. The wizard is configured for 500 kS/s conversion and this
// wrapper keeps one pair in DECIMATION input pairs (default: 100 kpair/s).
module xadc_dual_reader #(
    parameter integer unsigned DECIMATION = 5
) (
    input  wire         clk,
    input  wire         rst,

    input  wire         vp_in,
    input  wire         vn_in,
    input  wire         vauxp0,
    input  wire         vauxn0,
    input  wire         vauxp8,
    input  wire         vauxn8,

    output logic [11:0] sample_a,
    output logic [11:0] sample_b,
    output logic        sample_valid,
    output wire         xadc_busy
);

    localparam integer unsigned DECIMATION_SAFE =
        (DECIMATION < 1) ? 1 : DECIMATION;
    localparam integer unsigned DECIMATION_WIDTH =
        (DECIMATION_SAFE <= 1) ? 1 : $clog2(DECIMATION_SAFE);

    localparam logic [6:0] DRP_ADDR_VAUX0 = 7'h10;
    localparam logic [6:0] DRP_ADDR_VAUX8 = 7'h18;

    typedef enum logic [1:0] {
        READ_IDLE,
        READ_WAIT_A,
        READ_WAIT_B
    } read_state_t;

    read_state_t state;

    logic [6:0]  daddr;
    logic        den;
    wire         drdy;
    wire [15:0]  drp_data;
    wire         eos;
    logic [11:0] pending_a;
    logic [DECIMATION_WIDTH-1:0] decimation_count;

    xadc_dual_ao u_xadc_dual_ao (
        .di_in       (16'h0000),
        .daddr_in    (daddr),
        .den_in      (den),
        .dwe_in      (1'b0),
        .drdy_out    (drdy),
        .do_out      (drp_data),
        .dclk_in     (clk),
        .reset_in    (rst),
        .vp_in       (vp_in),
        .vn_in       (vn_in),
        .vauxp0      (vauxp0),
        .vauxn0      (vauxn0),
        .vauxp8      (vauxp8),
        .vauxn8      (vauxn8),
        .channel_out (),
        .eoc_out     (),
        .alarm_out   (),
        .eos_out     (eos),
        .busy_out    (xadc_busy)
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            state            <= READ_IDLE;
            daddr            <= DRP_ADDR_VAUX0;
            den              <= 1'b0;
            pending_a        <= 12'd0;
            sample_a         <= 12'd0;
            sample_b         <= 12'd0;
            sample_valid     <= 1'b0;
            decimation_count <= '0;
        end
        else begin
            den          <= 1'b0;
            sample_valid <= 1'b0;

            case (state)
                READ_IDLE: begin
                    if (eos) begin
                        daddr <= DRP_ADDR_VAUX0;
                        den   <= 1'b1;
                        state <= READ_WAIT_A;
                    end
                end

                READ_WAIT_A: begin
                    if (drdy) begin
                        pending_a <= drp_data[15:4];
                        daddr     <= DRP_ADDR_VAUX8;
                        den       <= 1'b1;
                        state     <= READ_WAIT_B;
                    end
                end

                READ_WAIT_B: begin
                    if (drdy) begin
                        if (decimation_count == DECIMATION_SAFE - 1) begin
                            sample_a         <= pending_a;
                            sample_b         <= drp_data[15:4];
                            sample_valid     <= 1'b1;
                            decimation_count <= '0;
                        end
                        else begin
                            decimation_count <= decimation_count + 1'b1;
                        end
                        state <= READ_IDLE;
                    end
                end

                default: state <= READ_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
