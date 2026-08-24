# X5-Y4: MAC pipeline with registered request control
export DESIGN_NAME = x5_y4_kimi
export PLATFORM = nangate45

# Paths relative to this config file
KIMI_ROOT := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))../..
export VERILOG_FILES = $(KIMI_ROOT)/rtl/x5_y4_kimi.v
export SDC_FILE = $(KIMI_ROOT)/flow/constraint_y4.sdc

export CORE_UTILIZATION = 18
export PLACE_DENSITY_LB_ADDON = 0.04
export TNS_END_PERCENT = 100
export SYNTH_REPEATABLE_BUILD = 1
export ABC_CLOCK_PERIOD_IN_PS = 1000
export GPL_TIMING_DRIVEN = 1
export GPL_ROUTABILITY_DRIVEN = 1
export GRT_ALLOW_CONGESTION = 0
export CAP_MARGIN = 50
export SLEW_MARGIN = 15
export NUM_CORES = 4
export ADDER_MAP_FILE :=
