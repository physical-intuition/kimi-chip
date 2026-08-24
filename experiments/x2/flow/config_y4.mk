export DESIGN_NAME = x2_y4_kimi
export PLATFORM = nangate45

export VERILOG_FILES = /home/kit/kimi-chip/experiments/x1/rtl/x1_y5_kimi.v \
                       /home/kit/kimi-chip/experiments/x2/rtl/x2_y4_kimi.v
export SDC_FILE = /home/kit/kimi-chip/experiments/x2/flow/constraint_y4.sdc

# Y1: CAP_MARGIN=20 left one extracted max-cap violation.
# Y3: CAP_MARGIN=25 closed cleanly with less area and higher fmax than margin 30.
# Refine the boundary at 22 to find the minimum clean repair margin.
export CORE_UTILIZATION = 20
export PLACE_DENSITY_LB_ADDON = 0.05
export TNS_END_PERCENT = 100
export SYNTH_REPEATABLE_BUILD = 1
export ABC_CLOCK_PERIOD_IN_PS = 2500
export GPL_ROUTABILITY_DRIVEN = 1
export GRT_ALLOW_CONGESTION = 0
export CAP_MARGIN = 22
export NUM_CORES = 4
export ADDER_MAP_FILE :=
