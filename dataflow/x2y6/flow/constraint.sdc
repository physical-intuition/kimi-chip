create_clock -name core_clock -period 0.55 [get_ports clk]
set_input_delay -clock core_clock 0.055 [all_inputs]
set_output_delay -clock core_clock 0.055 [all_outputs]
