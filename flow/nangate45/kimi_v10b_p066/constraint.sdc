set clk_period 0.66
create_clock -name clk -period $clk_period [get_ports clk]
set_input_delay  [expr $clk_period * 0.2] -clock clk [all_inputs]
set_output_delay [expr $clk_period * 0.2] -clock clk [all_outputs]
set_clock_uncertainty 0.1 [get_clocks clk]
set_false_path -from [get_ports rst_n]
