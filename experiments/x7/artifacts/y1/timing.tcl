read_liberty /home/kit/OpenROAD-flow-scripts/flow/platforms/nangate45/lib/NangateOpenCellLibrary_typical.lib
read_verilog artifacts/y1/x7_mapped.v
link_design x7_top
create_clock -name core_clk -period 2.000 [get_ports clk]
set_input_delay 0.0 -clock core_clk [all_inputs]
set_output_delay 0.0 -clock core_clk [all_outputs]
report_checks -path_delay max -format full_clock_expanded -digits 4
report_worst_slack -max -digits 4
report_tns -digits 4
exit
