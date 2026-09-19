set script_dir [file dirname [info script]]
set repo_root [file dirname $script_dir]
set four_edge_file [file join $repo_root rtl hall_four_edge_capture.sv]

if {[current_project -quiet] eq ""} {
    error "Open the main car2 project before sourcing this script"
}

if {[llength [get_files -quiet *hall_four_edge_capture.sv]] == 0} {
    add_files -norecurse $four_edge_file
}

set_property file_type SystemVerilog [get_files $four_edge_file]
set_property top hall_ao_monitor_top [get_filesets sources_1]
update_compile_order -fileset sources_1

puts "CAR2_FOUR_EDGE_INTEGRATION_READY"
puts "Added: $four_edge_file"
puts "Top: [get_property top [get_filesets sources_1]]"
