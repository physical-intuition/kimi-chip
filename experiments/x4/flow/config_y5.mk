export DESIGN_NAME = x4_y5_kimi
export PLATFORM = nangate45
export VERILOG_FILES = /home/kit/kimi-chip/experiments/x4/rtl/x4_y5_kimi.v
export SDC_FILE = /home/kit/kimi-chip/experiments/x4/flow/constraint_y5.sdc

# 880 MHz, below Y4's measured 900.93 MHz extracted ceiling. Y4's only
# signoff failures were two max-capacitance violations at CAP_MARGIN=22;
# raise the report-driven repair margin to the previously proven-clean 30.
export CORE_UTILIZATION = 18
export PLACE_DENSITY_LB_ADDON = 0.04
export TNS_END_PERCENT = 100
export SYNTH_REPEATABLE_BUILD = 1
export ABC_CLOCK_PERIOD_IN_PS = 1136
export GPL_TIMING_DRIVEN = 1
export GPL_ROUTABILITY_DRIVEN = 1
export GRT_ALLOW_CONGESTION = 0
export CAP_MARGIN = 30
export SLEW_MARGIN = 15
export NUM_CORES = 4
export ADDER_MAP_FILE :=
