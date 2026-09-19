set script_dir [file dirname [info script]]
set repo_root [file dirname $script_dir]
set project_dir [file join $repo_root build ao_sim]

create_project car2_ao_sim $project_dir \
    -part xc7z020clg484-2 \
    -force

set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

add_files -norecurse [list \
    [file join $repo_root rtl event_capture_buffer.sv] \
    [file join $repo_root rtl ao_capture_uart_exporter.sv] \
]

add_files -fileset sim_1 -norecurse \
    [file join $repo_root sim tb_ao_capture_pipeline.sv]

set_property top tb_ao_capture_pipeline [get_filesets sim_1]
update_compile_order -fileset sim_1

launch_simulation
run all
close_sim

puts "AO_SIMULATION_PASSED"
exit
