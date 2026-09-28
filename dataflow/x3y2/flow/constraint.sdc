create_clock -name core_clock -period 1.2 [get_ports clk]
set_input_delay -clock core_clock 0.12 [all_inputs]
set_output_delay -clock core_clock 0.12 [all_outputs]
