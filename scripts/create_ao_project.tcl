set script_dir [file dirname [info script]]
set repo_root [file dirname $script_dir]
set project_dir [file join $repo_root build car2]

file mkdir [file dirname $project_dir]

create_project car2 $project_dir \
    -part xc7z020clg484-2 \
    -force

set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

set rtl_files [list \
    [file join $repo_root rtl reset_controller.sv] \
    [file join $repo_root rtl hall_input_filter.sv] \
    [file join $repo_root rtl hall_four_edge_capture.sv] \
    [file join $repo_root rtl udiv64.sv] \
    [file join $repo_root rtl hall_gate_measure.sv] \
    [file join $repo_root rtl uart_tx_8n1.sv] \
    [file join $repo_root rtl tm1637_display.sv] \
    [file join $repo_root rtl xadc_dual_reader.sv] \
    [file join $repo_root rtl event_capture_buffer.sv] \
    [file join $repo_root rtl ao_capture_uart_exporter.sv] \
    [file join $repo_root rtl hall_ao_monitor_top.sv] \
]

add_files -norecurse $rtl_files
add_files -fileset constrs_1 -norecurse \
    [file join $repo_root constraints hall_gate_speed.xdc]

create_ip -name xadc_wiz -vendor xilinx.com -library ip \
    -module_name xadc_dual_ao

set_property -dict [list \
    CONFIG.INTERFACE_SELECTION {ENABLE_DRP} \
    CONFIG.DCLK_FREQUENCY {50} \
    CONFIG.ADC_CONVERSION_RATE {500} \
    CONFIG.XADC_STARUP_SELECTION {simultaneous_sampling} \
    CONFIG.CHANNEL_ENABLE_VP_VN {false} \
    CONFIG.CHANNEL_ENABLE_VAUXP0_VAUXN0 {true} \
    CONFIG.CHANNEL_ENABLE_VAUXP8_VAUXN8 {true} \
    CONFIG.ACQUISITION_TIME_VAUXP0_VAUXN0 {true} \
    CONFIG.ACQUISITION_TIME_VAUXP8_VAUXN8 {true} \
    CONFIG.AVERAGE_ENABLE_VAUXP0_VAUXN0 {false} \
    CONFIG.AVERAGE_ENABLE_VAUXP8_VAUXN8 {false} \
    CONFIG.BIPOLAR_VAUXP0_VAUXN0 {false} \
    CONFIG.BIPOLAR_VAUXP8_VAUXN8 {false} \
    CONFIG.ENABLE_TEMP_BUS {false} \
    CONFIG.VCCINT_ALARM {false} \
    CONFIG.VCCAUX_ALARM {false} \
    CONFIG.ENABLE_VBRAM_ALARM {false} \
    CONFIG.ENABLE_VCCPINT_ALARM {false} \
    CONFIG.ENABLE_VCCPAUX_ALARM {false} \
    CONFIG.ENABLE_VCCDDRO_ALARM {false} \
    CONFIG.OT_ALARM {false} \
    CONFIG.USER_TEMP_ALARM {false}] [get_ips xadc_dual_ao]

set xadc_xci [get_files [get_property IP_FILE [get_ips xadc_dual_ao]]]
set_property generate_synth_checkpoint false $xadc_xci
generate_target all $xadc_xci

create_ip -name ila -vendor xilinx.com -library ip \
    -module_name ila_ao_debug

set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {9} \
    CONFIG.C_DATA_DEPTH {8192} \
    CONFIG.C_EN_STRG_QUAL {1} \
    CONFIG.C_PROBE0_WIDTH {12} \
    CONFIG.C_PROBE1_WIDTH {12} \
    CONFIG.C_PROBE2_WIDTH {1} \
    CONFIG.C_PROBE3_WIDTH {1} \
    CONFIG.C_PROBE4_WIDTH {1} \
    CONFIG.C_PROBE5_WIDTH {1} \
    CONFIG.C_PROBE6_WIDTH {1} \
    CONFIG.C_PROBE7_WIDTH {1} \
    CONFIG.C_PROBE8_WIDTH {1}] [get_ips ila_ao_debug]

set ila_xci [get_files [get_property IP_FILE [get_ips ila_ao_debug]]]
set_property generate_synth_checkpoint false $ila_xci
generate_target all $ila_xci

set_property top hall_ao_monitor_top [get_filesets sources_1]
update_compile_order -fileset sources_1

puts "Created car2 dual-AO project: $project_dir"
puts "Top: hall_ao_monitor_top"
puts "Part: [get_property PART [current_project]]"
