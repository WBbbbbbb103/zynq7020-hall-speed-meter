set script_dir [file dirname [info script]]
source [file join $script_dir create_ao_project.tcl]

synth_design -top hall_ao_monitor_top -part xc7z020clg484-2
report_utilization -file [file join $repo_root build car2_utilization_synth.rpt]
report_timing_summary -file [file join $repo_root build car2_timing_synth.rpt]

puts "CAR2_SYNTH_CHECK_PASSED"
exit
