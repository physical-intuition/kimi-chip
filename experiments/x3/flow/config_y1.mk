export DESIGN_NAME = x3_y1_kimi
export PLATFORM = nangate45

export VERILOG_FILES = /home/kit/kimi-chip/experiments/x1/rtl/x1_y5_kimi.v \
                       /home/kit/kimi-chip/experiments/x3/rtl/x3_y1_kimi.v
export SDC_FILE = /home/kit/kimi-chip/experiments/x3/flow/constraint_y1.sdc

# X2-Y5 identified CAP_MARGIN=21 as a strict-clean candidate. X3-Y1 keeps that
# physical point while adding a locked functional oracle and failed-directions
# memory to the experiment system.
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
