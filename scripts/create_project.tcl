set script_dir [file dirname [info script]]
set repo_root [file dirname $script_dir]
set project_dir [file join $repo_root build vivado]

file mkdir [file dirname $project_dir]

create_project hall_gate_speed $project_dir \
    -part xc7z020clg484-2 \
    -force

set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

set rtl_files [list \
    [file join $repo_root rtl reset_controller.sv] \
    [file join $repo_root rtl hall_input_filter.sv] \
    [file join $repo_root rtl udiv64.sv] \
    [file join $repo_root rtl hall_gate_measure.sv] \
    [file join $repo_root rtl uart_tx_8n1.sv] \
    [file join $repo_root rtl uart_reporter.sv] \
    [file join $repo_root rtl tm1637_display.sv] \
    [file join $repo_root rtl hall_gate_speed_top.sv] \
]

add_files -norecurse $rtl_files
add_files -fileset constrs_1 -norecurse \
    [file join $repo_root constraints hall_gate_speed.xdc]
add_files -fileset sim_1 -norecurse \
    [file join $repo_root sim tb_hall_gate_speed.sv]

set_property top hall_gate_speed_top [get_filesets sources_1]
set_property top tb_hall_gate_speed [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "Created project: $project_dir"
puts "Part: [get_property PART [current_project]]"
