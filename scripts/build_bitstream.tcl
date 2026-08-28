set script_dir [file dirname [info script]]
set repo_root [file dirname $script_dir]
source [file join $script_dir create_project.tcl]

launch_runs synth_1 -jobs 4
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
if {![string match "*Complete*" $synth_status]} {
    error "Synthesis failed: $synth_status"
}

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
if {![string match "*Complete*" $impl_status]} {
    error "Implementation failed: $impl_status"
}

set reports_dir [file join $repo_root build reports]
file mkdir $reports_dir

open_run impl_1
report_timing_summary -file \
    [file join $reports_dir timing_summary.rpt]
report_drc -file \
    [file join $reports_dir drc.rpt]
report_utilization -file \
    [file join $reports_dir utilization.rpt]

puts "Bitstream: [file join $repo_root build vivado hall_gate_speed.runs impl_1 hall_gate_speed_top.bit]"
exit
