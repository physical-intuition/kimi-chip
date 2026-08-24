export DESIGN_NAME = x2_y2_kimi
export PLATFORM = nangate45

export VERILOG_FILES = /home/kit/kimi-chip/experiments/x1/rtl/x1_y5_kimi.v \
                       /home/kit/kimi-chip/experiments/x2/rtl/x2_y2_kimi.v
export SDC_FILE = /home/kit/kimi-chip/experiments/x2/flow/constraint_y2.sdc

# X2-Y1 retained one extracted max-cap violation with CAP_MARGIN=20.
# Raise the repair margin to 30 while preserving its verified RTL, floorplan,
# timing target, and executable X2 lint gates.
export CORE_UTILIZATION = 20
export PLACE_DENSITY_LB_ADDON = 0.05
export TNS_END_PERCENT = 100
export SYNTH_REPEATABLE_BUILD = 1
export ABC_CLOCK_PERIOD_IN_PS = 2500
export GPL_ROUTABILITY_DRIVEN = 1
export GRT_ALLOW_CONGESTION = 0
export CAP_MARGIN = 30
export NUM_CORES = 4
export ADDER_MAP_FILE :=
