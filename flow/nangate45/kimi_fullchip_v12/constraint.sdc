set clk_period 1.20
create_clock -name clk -period $clk_period [get_ports clk]
# input/output delays on data ports only; clk itself is not a timed data input
# (STA-0441: excluding the clock port from the input-delay set)
set data_inputs [remove_from_collection [all_inputs] [get_ports clk]]
set_input_delay  [expr $clk_period * 0.2] -clock clk $data_inputs
set_output_delay [expr $clk_period * 0.2] -clock clk [all_outputs]
set_clock_uncertainty 0.1 [get_clocks clk]
set_false_path -from [get_ports rst_n]
