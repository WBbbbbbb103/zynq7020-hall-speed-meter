set script_dir [file dirname [info script]]
source [file join $script_dir create_project.tcl]

launch_simulation
run all
close_sim

puts "Simulation completed. Check the log for ALL TESTS PASSED."
exit
