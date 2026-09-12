# X2Y5: Ultra-aggressive 0.6 ns target (~1.67 GHz)
create_clock [get_ports clk] -period 0.6 -name core_clock
set_input_delay 0.03 -clock core_clock [all_inputs]
set_output_delay 0.03 -clock core_clock [all_outputs]
