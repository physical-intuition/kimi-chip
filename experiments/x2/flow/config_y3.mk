export DESIGN_NAME = x2_y3_kimi
export PLATFORM = nangate45

export VERILOG_FILES = /home/kit/kimi-chip/experiments/x1/rtl/x1_y5_kimi.v \
                       /home/kit/kimi-chip/experiments/x2/rtl/x2_y3_kimi.v
export SDC_FILE = /home/kit/kimi-chip/experiments/x2/flow/constraint_y3.sdc

# Y1: CAP_MARGIN=20 left one final extracted max-cap violation.
# Y2: CAP_MARGIN=30 closed cleanly, but added 0.49% routed area and lost 0.46% fmax.
# Bisect at 25 to find a lower-overhead clean closure point.
export CORE_UTILIZATION = 20
export PLACE_DENSITY_LB_ADDON = 0.05
export TNS_END_PERCENT = 100
export SYNTH_REPEATABLE_BUILD = 1
export ABC_CLOCK_PERIOD_IN_PS = 2500
export GPL_ROUTABILITY_DRIVEN = 1
export GRT_ALLOW_CONGESTION = 0
export CAP_MARGIN = 25
export NUM_CORES = 4
export ADDER_MAP_FILE :=
