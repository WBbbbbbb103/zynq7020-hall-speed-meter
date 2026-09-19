`timescale 1ns / 1ps
`default_nettype none

// Exports two completed capture windows as fixed-width ASCII records:
//   #CAR2AO\r\n
//   D,STS,E,S\r\n
//   D,AON,0000000000000000\r\n
//   D,AOF,0000000000000000\r\n
//   D,BON,0000000000000000\r\n
//   D,BOF,0000000000000000\r\n
//   A,0000,ABC,DEF\r\n
//   ...
//   B,0000,ABC,DEF\r\n
//   ...
//   #END\r\n
// Each record contains event name, logical sample index, ADC A and ADC B.
module ao_capture_uart_exporter #(
    parameter integer unsigned DEPTH      = 16_384,
    parameter integer unsigned ADDR_WIDTH =
        (DEPTH <= 2) ? 1 : $clog2(DEPTH)
) (
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  capture_a_done,
    input  wire                  capture_b_done,
    input  wire                  edge_capture_done,
    input  wire                  edge_capture_error,
    input  wire [1:0]            edge_error_code,
    input  wire [3:0]            edge_seen,
    input  wire [63:0]           t_a_on,
    input  wire [63:0]           t_a_off,
    input  wire [63:0]           t_b_on,
    input  wire [63:0]           t_b_off,

    output logic                 capture_a_rd_en,
    output logic                 capture_b_rd_en,
    output logic [ADDR_WIDTH-1:0] capture_rd_index,
    input  wire [23:0]           capture_a_rd_data,
    input  wire [23:0]           capture_b_rd_data,

    input  wire                  tx_ready,
    output logic [7:0]           tx_data,
    output logic                 tx_valid,
    output logic                 export_busy,
    output logic                 export_done
);

    typedef enum logic [2:0] {
        WAIT_CAPTURE,
        SEND_HEADER,
        SEND_DIGITAL,
        READ_REQUEST,
        READ_WAIT,
        SEND_LINE,
        SEND_END,
        FINISHED
    } export_state_t;

    export_state_t state;
    logic event_b_selected;
    logic [2:0] digital_record;
    logic [4:0] byte_position;
    logic [23:0] current_sample;

    function automatic logic [7:0] hex_ascii(input logic [3:0] nibble);
        if (nibble < 10)
            hex_ascii = 8'h30 + nibble;
        else
            hex_ascii = 8'h41 + (nibble - 10);
    endfunction

    function automatic logic [7:0] header_byte(input logic [3:0] position);
        case (position)
            0: header_byte = "#";
            1: header_byte = "C";
            2: header_byte = "A";
            3: header_byte = "R";
            4: header_byte = "2";
            5: header_byte = "A";
            6: header_byte = "O";
            7: header_byte = 8'h0D;
            default: header_byte = 8'h0A;
        endcase
    endfunction

    function automatic logic [7:0] end_byte(input logic [2:0] position);
        case (position)
            0: end_byte = "#";
            1: end_byte = "E";
            2: end_byte = "N";
            3: end_byte = "D";
            4: end_byte = 8'h0D;
            default: end_byte = 8'h0A;
        endcase
    endfunction

    function automatic logic [7:0] digital_byte(
        input logic [2:0] record_number,
        input logic [4:0] position,
        input logic capture_error,
        input logic [1:0] capture_error_code,
        input logic [3:0] capture_seen,
        input logic [63:0] timestamp_a_on,
        input logic [63:0] timestamp_a_off,
        input logic [63:0] timestamp_b_on,
        input logic [63:0] timestamp_b_off
    );
        logic [63:0] selected_timestamp;
        logic [7:0] label_0;
        logic [7:0] label_1;
        logic [7:0] label_2;
        begin
            case (record_number)
                1: begin
                    selected_timestamp = timestamp_a_on;
                    label_0 = "A"; label_1 = "O"; label_2 = "N";
                end
                2: begin
                    selected_timestamp = timestamp_a_off;
                    label_0 = "A"; label_1 = "O"; label_2 = "F";
                end
                3: begin
                    selected_timestamp = timestamp_b_on;
                    label_0 = "B"; label_1 = "O"; label_2 = "N";
                end
                default: begin
                    selected_timestamp = timestamp_b_off;
                    label_0 = "B"; label_1 = "O"; label_2 = "F";
                end
            endcase

            if (record_number == 0) begin
                case (position)
                    0: digital_byte = "D";
                    1: digital_byte = ",";
                    2: digital_byte = "S";
                    3: digital_byte = "T";
                    4: digital_byte = "S";
                    5: digital_byte = ",";
                    6: digital_byte = hex_ascii({1'b0, capture_error_code, capture_error});
                    7: digital_byte = ",";
                    8: digital_byte = hex_ascii(capture_seen);
                    9: digital_byte = 8'h0D;
                    default: digital_byte = 8'h0A;
                endcase
            end
            else begin
                case (position)
                    0:  digital_byte = "D";
                    1:  digital_byte = ",";
                    2:  digital_byte = label_0;
                    3:  digital_byte = label_1;
                    4:  digital_byte = label_2;
                    5:  digital_byte = ",";
                    6:  digital_byte = hex_ascii(selected_timestamp[63:60]);
                    7:  digital_byte = hex_ascii(selected_timestamp[59:56]);
                    8:  digital_byte = hex_ascii(selected_timestamp[55:52]);
                    9:  digital_byte = hex_ascii(selected_timestamp[51:48]);
                    10: digital_byte = hex_ascii(selected_timestamp[47:44]);
                    11: digital_byte = hex_ascii(selected_timestamp[43:40]);
                    12: digital_byte = hex_ascii(selected_timestamp[39:36]);
                    13: digital_byte = hex_ascii(selected_timestamp[35:32]);
                    14: digital_byte = hex_ascii(selected_timestamp[31:28]);
                    15: digital_byte = hex_ascii(selected_timestamp[27:24]);
                    16: digital_byte = hex_ascii(selected_timestamp[23:20]);
                    17: digital_byte = hex_ascii(selected_timestamp[19:16]);
                    18: digital_byte = hex_ascii(selected_timestamp[15:12]);
                    19: digital_byte = hex_ascii(selected_timestamp[11:8]);
                    20: digital_byte = hex_ascii(selected_timestamp[7:4]);
                    21: digital_byte = hex_ascii(selected_timestamp[3:0]);
                    22: digital_byte = 8'h0D;
                    default: digital_byte = 8'h0A;
                endcase
            end
        end
    endfunction

    function automatic logic [7:0] line_byte(
        input logic event_b,
        input logic [15:0] index,
        input logic [23:0] sample,
        input logic [4:0] position
    );
        case (position)
            0:  line_byte = event_b ? "B" : "A";
            1:  line_byte = ",";
            2:  line_byte = hex_ascii(index[15:12]);
            3:  line_byte = hex_ascii(index[11:8]);
            4:  line_byte = hex_ascii(index[7:4]);
            5:  line_byte = hex_ascii(index[3:0]);
            6:  line_byte = ",";
            7:  line_byte = hex_ascii(sample[23:20]);
            8:  line_byte = hex_ascii(sample[19:16]);
            9:  line_byte = hex_ascii(sample[15:12]);
            10: line_byte = ",";
            11: line_byte = hex_ascii(sample[11:8]);
            12: line_byte = hex_ascii(sample[7:4]);
            13: line_byte = hex_ascii(sample[3:0]);
            14: line_byte = 8'h0D;
            default: line_byte = 8'h0A;
        endcase
    endfunction

    always_comb begin
        capture_a_rd_en = 1'b0;
        capture_b_rd_en = 1'b0;
        tx_valid        = 1'b0;
        tx_data         = 8'h00;
        export_busy     = (state != WAIT_CAPTURE) && (state != FINISHED);
        export_done     = (state == FINISHED);

        case (state)
            SEND_HEADER: begin
                tx_valid = 1'b1;
                tx_data  = header_byte(byte_position[3:0]);
            end

            SEND_DIGITAL: begin
                tx_valid = 1'b1;
                tx_data = digital_byte(
                    digital_record,
                    byte_position,
                    edge_capture_error,
                    edge_error_code,
                    edge_seen,
                    t_a_on,
                    t_a_off,
                    t_b_on,
                    t_b_off
                );
            end

            READ_REQUEST: begin
                capture_a_rd_en = !event_b_selected;
                capture_b_rd_en = event_b_selected;
            end

            SEND_LINE: begin
                tx_valid = 1'b1;
                tx_data  = line_byte(
                    event_b_selected,
                    {{(16-ADDR_WIDTH){1'b0}}, capture_rd_index},
                    current_sample,
                    byte_position
                );
            end

            SEND_END: begin
                tx_valid = 1'b1;
                tx_data  = end_byte(byte_position[2:0]);
            end

            default: begin
            end
        endcase
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state             <= WAIT_CAPTURE;
            event_b_selected  <= 1'b0;
            digital_record    <= '0;
            byte_position     <= '0;
            capture_rd_index  <= '0;
            current_sample    <= '0;
        end
        else begin
            case (state)
                WAIT_CAPTURE: begin
                    if (capture_a_done && capture_b_done && edge_capture_done) begin
                        byte_position <= '0;
                        state <= SEND_HEADER;
                    end
                end

                SEND_HEADER: begin
                    if (tx_valid && tx_ready) begin
                        if (byte_position == 8) begin
                            byte_position  <= '0;
                            digital_record <= '0;
                            state <= SEND_DIGITAL;
                        end
                        else begin
                            byte_position <= byte_position + 1'b1;
                        end
                    end
                end

                SEND_DIGITAL: begin
                    if (tx_valid && tx_ready) begin
                        if (((digital_record == 0) && (byte_position == 10)) ||
                            ((digital_record != 0) && (byte_position == 23))) begin
                            byte_position <= '0;
                            if (digital_record == 4) begin
                                event_b_selected <= 1'b0;
                                capture_rd_index <= '0;
                                state <= READ_REQUEST;
                            end
                            else begin
                                digital_record <= digital_record + 1'b1;
                            end
                        end
                        else begin
                            byte_position <= byte_position + 1'b1;
                        end
                    end
                end

                READ_REQUEST: begin
                    state <= READ_WAIT;
                end

                READ_WAIT: begin
                    current_sample <= event_b_selected
                        ? capture_b_rd_data
                        : capture_a_rd_data;
                    byte_position <= '0;
                    state <= SEND_LINE;
                end

                SEND_LINE: begin
                    if (tx_valid && tx_ready) begin
                        if (byte_position == 15) begin
                            byte_position <= '0;
                            if (capture_rd_index == DEPTH - 1) begin
                                if (!event_b_selected) begin
                                    event_b_selected <= 1'b1;
                                    capture_rd_index <= '0;
                                    state <= READ_REQUEST;
                                end
                                else begin
                                    state <= SEND_END;
                                end
                            end
                            else begin
                                capture_rd_index <= capture_rd_index + 1'b1;
                                state <= READ_REQUEST;
                            end
                        end
                        else begin
                            byte_position <= byte_position + 1'b1;
                        end
                    end
                end

                SEND_END: begin
                    if (tx_valid && tx_ready) begin
                        if (byte_position == 5) begin
                            byte_position <= '0;
                            state <= FINISHED;
                        end
                        else begin
                            byte_position <= byte_position + 1'b1;
                        end
                    end
                end

                FINISHED: begin
                end

                default: state <= WAIT_CAPTURE;
            endcase
        end
    end

endmodule

`default_nettype wire
