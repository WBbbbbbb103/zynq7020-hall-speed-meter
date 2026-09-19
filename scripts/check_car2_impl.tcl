set script_dir [file dirname [info script]]
source [file join $script_dir create_ao_project.tcl]

synth_design -top hall_ao_monitor_top -part xc7z020clg484-2
opt_design
place_design
phys_opt_design
route_design

set reports_dir [file join $repo_root build car2_reports]
file mkdir $reports_dir

report_utilization -file \
    [file join $reports_dir utilization_impl.rpt]
report_timing_summary -file \
    [file join $reports_dir timing_summary_impl.rpt]
report_drc -file \
    [file join $reports_dir drc_impl.rpt]

if {[get_property SLACK [get_timing_paths -delay_type max -max_paths 1]] < 0} {
    error "CAR2 implementation has negative setup slack"
}

write_checkpoint -force \
    [file join $repo_root build car2_routed.dcp]

puts "CAR2_IMPLEMENTATION_CHECK_PASSED"
exit
