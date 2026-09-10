# SDC constraints for audit_top
# Target: 100 MHz (10 ns period) for X1Y1 baseline

create_clock [get_ports clk] -period 10.000 -name clk

# Input/output delays (conservative)
set_input_delay 0.5 -clock clk [all_inputs]
set_output_delay 0.5 -clock clk [all_outputs]

# Don't optimize clock
set_dont_touch_network [get_clocks clk]
