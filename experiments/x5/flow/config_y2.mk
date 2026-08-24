# X5-Y2 deliberately holds X5-Y1 target to test the observed failing cone.
export DESIGN_NAME = x5_y2_kimi
export PLATFORM = nangate45
export VERILOG_FILES = /home/kit/kimi-chip/experiments/x5/rtl/x5_y2_kimi.v
export SDC_FILE = /home/kit/kimi-chip/experiments/x5/flow/constraint_y2.sdc
export CORE_UTILIZATION = 18
export PLACE_DENSITY_LB_ADDON = 0.04
export TNS_END_PERCENT = 100
export SYNTH_REPEATABLE_BUILD = 1
export ABC_CLOCK_PERIOD_IN_PS = 1068
export GPL_TIMING_DRIVEN = 1
export GPL_ROUTABILITY_DRIVEN = 1
export GRT_ALLOW_CONGESTION = 0
export CAP_MARGIN = 30
export SLEW_MARGIN = 15
export NUM_CORES = 4
export ADDER_MAP_FILE :=
