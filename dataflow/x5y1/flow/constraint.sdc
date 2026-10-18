create_clock -name core_clock -period 0.55 [get_ports clk]
set_input_delay -clock core_clock 0.06 [all_inputs]
set_output_delay -clock core_clock 0.06 [all_outputs]
# X4Y5: reset is async; recovery/removal on rst_n deassertion is not a datapath path
set_false_path -from [get_ports rst_n]
