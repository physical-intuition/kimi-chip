export DESIGN_NAME = x3_y5_kimi
export PLATFORM = nangate45

export VERILOG_FILES = /home/kit/kimi-chip/experiments/x1/rtl/x1_y5_kimi.v \
                       /home/kit/kimi-chip/experiments/x3/rtl/x3_y5_kimi.v
export SDC_FILE = /home/kit/kimi-chip/experiments/x3/flow/constraint_y5.sdc

# X3-Y5 keeps the proven CAP_MARGIN=21 physical point while locking reset-abort
# and clean-restart behavior against stale requests, writes, and accumulator state.
export CORE_UTILIZATION = 20
export PLACE_DENSITY_LB_ADDON = 0.05
export TNS_END_PERCENT = 100
export SYNTH_REPEATABLE_BUILD = 1
export ABC_CLOCK_PERIOD_IN_PS = 2500
export GPL_ROUTABILITY_DRIVEN = 1
export GRT_ALLOW_CONGESTION = 0
export CAP_MARGIN = 21
export NUM_CORES = 4
export ADDER_MAP_FILE :=
