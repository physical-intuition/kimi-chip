create_clock -name core_clock -period 1.0 [get_ports clk]
set_input_delay -clock core_clock 0.1 [all_inputs]
set_output_delay -clock core_clock 0.1 [all_outputs]
