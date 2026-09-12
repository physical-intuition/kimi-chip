# X2Y4: Aggressive 1 GHz target (1.0 ns period)
create_clock [get_ports clk] -period 1.0 -name core_clock
set_input_delay 0.05 -clock core_clock [all_inputs]
set_output_delay 0.05 -clock core_clock [all_outputs]
