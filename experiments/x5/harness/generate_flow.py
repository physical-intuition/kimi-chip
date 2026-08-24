#!/usr/bin/env python3
import json, math
from pathlib import Path
root=Path('/home/kit/kimi-chip'); x5=root/'experiments/x5'
p=json.loads((x5/'harness/y1_policy.json').read_text())
f=float(p['derived_target_frequency_mhz']); period=1000.0/f; abc=math.ceil(period*1000)
(x5/'flow').mkdir(parents=True,exist_ok=True)
(x5/'flow/constraint_y1.sdc').write_text(f'''set clk_name core_clock
set clk_port_name clk
set clk_period {period:.9f}
set clk_io_pct 0.2
set clk_port [get_ports $clk_port_name]
create_clock -name $clk_name -period $clk_period $clk_port
set non_clock_inputs [lsearch -inline -all -not -exact [all_inputs] $clk_port]
set_input_delay [expr $clk_period * $clk_io_pct] -clock $clk_name $non_clock_inputs
set_output_delay [expr $clk_period * $clk_io_pct] -clock $clk_name [all_outputs]
''')
(x5/'flow/config_y1.mk').write_text(f'''# Generated from experiments/x5/harness/y1_policy.json. Do not set target manually.
export DESIGN_NAME = x5_y1_kimi
export PLATFORM = nangate45
export VERILOG_FILES = /home/kit/kimi-chip/experiments/x5/rtl/x5_y1_kimi.v
export SDC_FILE = /home/kit/kimi-chip/experiments/x5/flow/constraint_y1.sdc
export CORE_UTILIZATION = 18
export PLACE_DENSITY_LB_ADDON = 0.04
export TNS_END_PERCENT = 100
export SYNTH_REPEATABLE_BUILD = 1
export ABC_CLOCK_PERIOD_IN_PS = {abc}
export GPL_TIMING_DRIVEN = 1
export GPL_ROUTABILITY_DRIVEN = 1
export GRT_ALLOW_CONGESTION = 0
export CAP_MARGIN = 30
export SLEW_MARGIN = 15
export NUM_CORES = 4
export ADDER_MAP_FILE :=
''')
print(f'DERIVED_FLOW target_mhz={f:.3f} period_ns={period:.9f} abc_ps={abc}')
