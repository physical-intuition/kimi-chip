create_clock -name core_clock -period 0.8 [get_ports clk]
set_input_delay -clock core_clock 0.08 [all_inputs]
set_output_delay -clock core_clock 0.08 [all_outputs]
