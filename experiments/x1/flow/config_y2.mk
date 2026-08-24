export DESIGN_NAME = x1_y2_kimi
export PLATFORM = nangate45

export VERILOG_FILES = /home/kit/kimi-chip/experiments/x1/rtl/x1_y2_kimi.v
export SDC_FILE = /home/kit/kimi-chip/experiments/x1/flow/constraint_y2.sdc

# Deliberately loose floorplan. Y1 proved routing, not area, is the first gate.
export CORE_UTILIZATION = 20
export PLACE_DENSITY_LB_ADDON = 0.05
export TNS_END_PERCENT = 100
export SYNTH_REPEATABLE_BUILD = 1
export ABC_CLOCK_PERIOD_IN_PS = 5000
export GPL_ROUTABILITY_DRIVEN = 1
export GRT_ALLOW_CONGESTION = 0
# Detailed routing exceeded this sandbox's memory budget with three workers.
# One worker trades runtime for a much smaller peak working set.
export NUM_CORES = 1

export ADDER_MAP_FILE :=
