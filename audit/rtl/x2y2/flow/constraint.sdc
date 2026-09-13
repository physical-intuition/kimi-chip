# X1 baseline: 100 MHz target (10 ns period)
create_clock [get_ports clk] -period 10.0 -name core_clock
set_input_delay 0.5 -clock core_clock [all_inputs]
set_output_delay 0.5 -clock core_clock [all_outputs]
