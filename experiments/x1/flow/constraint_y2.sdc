current_design x1_y2_kimi

set clk_period 5.0
create_clock -name core_clock -period $clk_period [get_ports clk]
set_clock_uncertainty 0.10 [get_clocks core_clock]
set_false_path -from [get_ports rst_n]

set non_clock_inputs [all_inputs -no_clocks]
set_input_delay 1.0 -clock core_clock $non_clock_inputs
set_output_delay 1.0 -clock core_clock [all_outputs]
