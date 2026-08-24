export DESIGN_NAME = x2_y5_kimi
export PLATFORM = nangate45

export VERILOG_FILES = /home/kit/kimi-chip/experiments/x1/rtl/x1_y5_kimi.v \
                       /home/kit/kimi-chip/experiments/x2/rtl/x2_y5_kimi.v
export SDC_FILE = /home/kit/kimi-chip/experiments/x2/flow/constraint_y5.sdc

# Y1: CAP_MARGIN=20 left one extracted max-cap violation.
# Y4: CAP_MARGIN=22 closed cleanly and improved both area and fmax over margin 25.
# Test the intervening integer margin to identify the minimum observed clean boundary.
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
