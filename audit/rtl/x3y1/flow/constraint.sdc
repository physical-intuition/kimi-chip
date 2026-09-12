# X3Y1: Harness-driven 0.582ns target
# Based on X2Y5 achieving 0.53ns with 0.07ns slack
create_clock [get_ports clk] -period 0.582 -name core_clock
set_input_delay 0.029 -clock core_clock [all_inputs]
set_output_delay 0.029 -clock core_clock [all_outputs]
