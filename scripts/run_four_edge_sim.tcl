set script_dir [file dirname [info script]]
set repo_root [file dirname $script_dir]
set project_dir [file join $repo_root build four_edge_sim]

create_project car2_four_edge_sim $project_dir \
    -part xc7z020clg484-2 \
    -force

set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

add_files -norecurse \
    [file join $repo_root rtl hall_four_edge_capture.sv]

add_files -fileset sim_1 -norecurse \
    [file join $repo_root sim tb_hall_four_edge_capture.sv]

set_property top tb_hall_four_edge_capture [get_filesets sim_1]
update_compile_order -fileset sim_1

launch_simulation
run all
close_sim

puts "FOUR_EDGE_SIMULATION_PASSED"
exit
