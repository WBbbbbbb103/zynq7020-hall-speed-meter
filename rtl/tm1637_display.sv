`timescale 1ns / 1ps
`default_nettype none

module tm1637_display #(
    parameter integer unsigned CLK_HZ     = 50_000_000,
    parameter integer unsigned REFRESH_HZ = 100,
    parameter integer unsigned STEP_HZ    = 100_000,
    parameter logic [2:0]      BRIGHTNESS = 3'd3
) (
    input  wire        clk,
    input  wire        rst,
    input  wire [13:0] value,
    output logic       tm_clk,
    output wire        tm_dio
);

    localparam integer unsigned REFRESH_CYCLES_RAW =
        CLK_HZ / REFRESH_HZ;
    localparam integer unsigned REFRESH_CYCLES =
        (REFRESH_CYCLES_RAW < 1) ? 1 : REFRESH_CYCLES_RAW;
    localparam integer unsigned STEP_CYCLES_RAW =
        CLK_HZ / STEP_HZ;
    localparam integer unsigned STEP_CYCLES =
        (STEP_CYCLES_RAW < 1) ? 1 : STEP_CYCLES_RAW;
    localparam integer unsigned REFRESH_WIDTH =
        (REFRESH_CYCLES <= 1) ? 1 : $clog2(REFRESH_CYCLES);
    localparam integer unsigned STEP_WIDTH =
        (STEP_CYCLES <= 1) ? 1 : $clog2(STEP_CYCLES);

    typedef enum logic [3:0] {
        STATE_IDLE,
        STATE_START_1,
        STATE_START_2,
        STATE_START_3,
        STATE_BIT_SETUP,
        STATE_BIT_HIGH,
        STATE_BIT_LOW,
        STATE_ACK_RELEASE,
        STATE_ACK_HIGH,
        STATE_ACK_LOW,
        STATE_STOP_1,
        STATE_STOP_2,
        STATE_STOP_3
    } state_t;

    state_t state;
    logic [REFRESH_WIDTH-1:0] refresh_count;
    logic [STEP_WIDTH-1:0] step_count;
    logic step_tick;
    logic dio_drive_low;
    logic [2:0] byte_index;
    logic [2:0] bit_index;
    logic [13:0] value_latched;
    logic [7:0] current_byte;
    logic [3:0] digit_thousands;
    logic [3:0] digit_hundreds;
    logic [3:0] digit_tens;
    logic [3:0] digit_ones;

    function automatic logic [7:0] segment_code(
        input logic [3:0] digit
    );
        begin
            case (digit)
                4'd0: segment_code = 8'h3F;
                4'd1: segment_code = 8'h06;
                4'd2: segment_code = 8'h5B;
                4'd3: segment_code = 8'h4F;
                4'd4: segment_code = 8'h66;
                4'd5: segment_code = 8'h6D;
                4'd6: segment_code = 8'h7D;
                4'd7: segment_code = 8'h07;
                4'd8: segment_code = 8'h7F;
                4'd9: segment_code = 8'h6F;
                default: segment_code = 8'h00;
            endcase
        end
    endfunction

    always_comb begin
        digit_thousands = value_latched / 1000;
        digit_hundreds  = (value_latched / 100) % 10;
        digit_tens      = (value_latched / 10) % 10;
        digit_ones      = value_latched % 10;
    end

    always_comb begin
        case (byte_index)
            3'd0: current_byte = 8'h40;
            3'd1: current_byte = 8'hC0;
            3'd2: current_byte = segment_code(digit_thousands);
            3'd3: current_byte = segment_code(digit_hundreds);
            3'd4: current_byte = segment_code(digit_tens);
            3'd5: current_byte = segment_code(digit_ones);
            default: current_byte = 8'h88 | {5'b00000, BRIGHTNESS};
        endcase
    end

    // Open-drain-style output: drive low or release to high impedance. This
    // implementation does not sample the TM1637 ACK, so no input buffer is
    // required. The external level shifter/pull-up creates each high level.
    assign tm_dio = dio_drive_low ? 1'b0 : 1'bz;

    always_ff @(posedge clk) begin
        if (rst) begin
            step_count <= '0;
            step_tick  <= 1'b0;
        end
        else if (step_count == STEP_CYCLES - 1) begin
            step_count <= '0;
            step_tick  <= 1'b1;
        end
        else begin
            step_count <= step_count + 1'b1;
            step_tick  <= 1'b0;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state         <= STATE_IDLE;
            refresh_count <= '0;
            tm_clk        <= 1'b1;
            dio_drive_low <= 1'b0;
            byte_index    <= 3'd0;
            bit_index     <= 3'd0;
            value_latched <= 14'd0;
        end
        else begin
            if (state == STATE_IDLE) begin
                if (refresh_count == REFRESH_CYCLES - 1) begin
                    refresh_count <= '0;
                    value_latched <=
                        (value > 14'd9999) ? 14'd9999 : value;
                    byte_index <= 3'd0;
                    state      <= STATE_START_1;
                end
                else begin
                    refresh_count <= refresh_count + 1'b1;
                end
            end

            if (step_tick) begin
                case (state)
                    STATE_IDLE: begin
                        tm_clk        <= 1'b1;
                        dio_drive_low <= 1'b0;
                    end
                    STATE_START_1: begin
                        tm_clk        <= 1'b1;
                        dio_drive_low <= 1'b0;
                        state         <= STATE_START_2;
                    end
                    STATE_START_2: begin
                        tm_clk        <= 1'b1;
                        dio_drive_low <= 1'b1;
                        state         <= STATE_START_3;
                    end
                    STATE_START_3: begin
                        tm_clk    <= 1'b0;
                        bit_index <= 3'd0;
                        state     <= STATE_BIT_SETUP;
                    end
                    STATE_BIT_SETUP: begin
                        tm_clk        <= 1'b0;
                        dio_drive_low <= !current_byte[bit_index];
                        state         <= STATE_BIT_HIGH;
                    end
                    STATE_BIT_HIGH: begin
                        tm_clk <= 1'b1;
                        state  <= STATE_BIT_LOW;
                    end
                    STATE_BIT_LOW: begin
                        tm_clk <= 1'b0;
                        if (bit_index == 3'd7) begin
                            state <= STATE_ACK_RELEASE;
                        end
                        else begin
                            bit_index <= bit_index + 1'b1;
                            state     <= STATE_BIT_SETUP;
                        end
                    end
                    STATE_ACK_RELEASE: begin
                        tm_clk        <= 1'b0;
                        dio_drive_low <= 1'b0;
                        state         <= STATE_ACK_HIGH;
                    end
                    STATE_ACK_HIGH: begin
                        tm_clk <= 1'b1;
                        state  <= STATE_ACK_LOW;
                    end
                    STATE_ACK_LOW: begin
                        tm_clk <= 1'b0;
                        if ((byte_index >= 3'd1) &&
                            (byte_index < 3'd5)) begin
                            byte_index <= byte_index + 1'b1;
                            bit_index  <= 3'd0;
                            state      <= STATE_BIT_SETUP;
                        end
                        else begin
                            state <= STATE_STOP_1;
                        end
                    end
                    STATE_STOP_1: begin
                        tm_clk        <= 1'b0;
                        dio_drive_low <= 1'b1;
                        state         <= STATE_STOP_2;
                    end
                    STATE_STOP_2: begin
                        tm_clk <= 1'b1;
                        state  <= STATE_STOP_3;
                    end
                    STATE_STOP_3: begin
                        dio_drive_low <= 1'b0;
                        if (byte_index == 3'd0) begin
                            byte_index <= 3'd1;
                            state      <= STATE_START_1;
                        end
                        else if (byte_index == 3'd5) begin
                            byte_index <= 3'd6;
                            state      <= STATE_START_1;
                        end
                        else begin
                            state <= STATE_IDLE;
                        end
                    end
                    default: begin
                        state <= STATE_IDLE;
                    end
                endcase
            end
        end
    end

endmodule

`default_nettype wire
