## LXB-ZYNQ7000 / XC7Z020-2CLG484I
## Vivado part: xc7z020clg484-2

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

## ============================================================
## On-board 50 MHz PL clock: PL_CLK_50M
## ============================================================

set_property -dict {
    PACKAGE_PIN M19
    IOSTANDARD LVCMOS33
} [get_ports clk_50m]

create_clock -name clk_50m -period 20.000 [get_ports clk_50m]


## ============================================================
## Hall digital inputs
## Hall A: GPIO2 pin 39, FPGA G15
## Hall B: GPIO2 pin 40, FPGA G16
## ============================================================

set_property -dict {
    PACKAGE_PIN G15
    IOSTANDARD LVCMOS33
    PULLUP TRUE
} [get_ports hall_a_in]

set_property -dict {
    PACKAGE_PIN G16
    IOSTANDARD LVCMOS33
    PULLUP TRUE
} [get_ports hall_b_in]


## ============================================================
## XADC dual analog inputs
##
## VAUX0:
##   vauxp0 = F16
##   vauxn0 = E16
##
## VAUX8:
##   vauxp8 = D16
##   vauxn8 = D17
##
## Bank 35 uses 3.3 V VCCO, so the VAUX ports must use an
## IOSTANDARD compatible with this bank.
##
## This IOSTANDARD setting does not change the XADC analog
## measurement range. The voltage entering VAUXP must still
## remain within 0 to 1.0 V in unipolar mode.
## ============================================================

set_property -dict {
    PACKAGE_PIN F16
    IOSTANDARD LVCMOS33
} [get_ports vauxp0]

set_property -dict {
    PACKAGE_PIN E16
    IOSTANDARD LVCMOS33
} [get_ports vauxn0]

set_property -dict {
    PACKAGE_PIN D16
    IOSTANDARD LVCMOS33
} [get_ports vauxp8]

set_property -dict {
    PACKAGE_PIN D17
    IOSTANDARD LVCMOS33
} [get_ports vauxn8]


## ============================================================
## TM1637 interface
## Use a 3.3 V / 5 V bidirectional level-shifter module.
## ============================================================

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


## ============================================================
## On-board CH340 USB-UART
## FPGA L17 -> CH340 RX -> USB-C -> computer
## ============================================================

set_property -dict {
    PACKAGE_PIN L17
    IOSTANDARD LVCMOS33
    DRIVE 8
    SLEW SLOW
} [get_ports uart_tx]


## ============================================================
## KEY1, active low
## ============================================================

set_property -dict {
    PACKAGE_PIN K21
    IOSTANDARD LVCMOS33
    PULLUP TRUE
} [get_ports pl_key1_n]


## ============================================================
## On-board status LEDs, active high
## ============================================================

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


## ============================================================
## Timing exceptions
## ============================================================

## These inputs pass through two-stage synchronizers in RTL.
set_false_path \
    -from [get_ports {hall_a_in hall_b_in pl_key1_n}]

## These board-local outputs do not use an external synchronous
## capture clock.
set_false_path \
    -to [get_ports {uart_tx pl_led1 pl_led2 tm_clk tm_dio}]