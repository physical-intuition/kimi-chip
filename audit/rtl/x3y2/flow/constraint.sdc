# X3Y2: Harness-driven 0.565ns target
create_clock [get_ports clk] -period 0.565 -name core_clock
set_input_delay 0.028 -clock core_clock [all_inputs]
set_output_delay 0.028 -clock core_clock [all_outputs]
