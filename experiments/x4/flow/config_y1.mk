export DESIGN_NAME = x4_y1_kimi
export PLATFORM = nangate45
export VERILOG_FILES = /home/kit/kimi-chip/experiments/x4/rtl/x4_y1_kimi.v
export SDC_FILE = /home/kit/kimi-chip/experiments/x4/flow/constraint_y1.sdc

# 752 MHz v9/v10 hierarchical-fold baseline. Lower density leaves timing-driven
# placement and repair room for the substantially tighter 1.329787 ns target.
export CORE_UTILIZATION = 18
export PLACE_DENSITY_LB_ADDON = 0.04
export TNS_END_PERCENT = 100
export SYNTH_REPEATABLE_BUILD = 1
export ABC_CLOCK_PERIOD_IN_PS = 1330
export GPL_TIMING_DRIVEN = 1
export GPL_ROUTABILITY_DRIVEN = 1
export GRT_ALLOW_CONGESTION = 0
export CAP_MARGIN = 22
export SLEW_MARGIN = 15
export NUM_CORES = 4
export ADDER_MAP_FILE :=
