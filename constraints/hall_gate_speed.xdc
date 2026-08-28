## LXB-ZYNQ7000 / XC7Z020-2CLG484I
## Vivado part: xc7z020clg484-2

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

## On-board 50 MHz PL clock: PL_CLK_50M
set_property -dict {
    PACKAGE_PIN M19
    IOSTANDARD LVCMOS33
} [get_ports clk_50m]

create_clock -name clk_50m -period 20.000 [get_ports clk_50m]

## Hall gates. Board silks: G15 and F16.
set_property -dict {
    PACKAGE_PIN G15
    IOSTANDARD LVCMOS33
    PULLUP TRUE
} [get_ports hall_a_in]

set_property -dict {
    PACKAGE_PIN F16
    IOSTANDARD LVCMOS33
    PULLUP TRUE
} [get_ports hall_b_in]

## TM1637 interface. Use a 3.3 V / 5 V bidirectional level shifter.
set_property -dict {
    PACKAGE_PIN C19
    IOSTANDARD LVCMOS33
    DRIVE 4
    SLEW SLOW
} [get_ports tm_clk]

set_property -dict {
    PACKAGE_PIN D18
    IOSTANDARD LVCMOS33
    DRIVE 4
    SLEW SLOW
    PULLUP TRUE
} [get_ports tm_dio]

## On-board CH340: FPGA L17 -> CH340 RX -> USB-C -> computer.
set_property -dict {
    PACKAGE_PIN L17
    IOSTANDARD LVCMOS33
    DRIVE 8
    SLEW SLOW
} [get_ports uart_tx]

## KEY1, active low.
set_property -dict {
    PACKAGE_PIN K21
    IOSTANDARD LVCMOS33
    PULLUP TRUE
} [get_ports pl_key1_n]

## On-board status LEDs, active high.
set_property -dict {
    PACKAGE_PIN P20
    IOSTANDARD LVCMOS33
    DRIVE 8
    SLEW SLOW
} [get_ports pl_led1]

set_property -dict {
    PACKAGE_PIN P21
    IOSTANDARD LVCMOS33
    DRIVE 8
    SLEW SLOW
} [get_ports pl_led2]

## These inputs pass through two-stage synchronizers in RTL.
set_false_path -from [get_ports {hall_a_in hall_b_in pl_key1_n}]

## These board-local interfaces are asynchronous to the 50 MHz PL clock and
## do not have an external synchronous capture clock.
set_false_path -to [get_ports {uart_tx pl_led1 pl_led2 tm_clk tm_dio}]
