export DESIGN_NAME = x1_y1_kimi
export PLATFORM = nangate45

export VERILOG_FILES = /home/kit/kimi-chip/experiments/x1/rtl/x1_y1_kimi.v
export SDC_FILE = /home/kit/kimi-chip/experiments/x1/flow/constraint.sdc

export CORE_UTILIZATION = 40
export PLACE_DENSITY_LB_ADDON = 0.10
export TNS_END_PERCENT = 100
export SYNTH_REPEATABLE_BUILD = 1
export ABC_CLOCK_PERIOD_IN_PS = 5000

# The baseline is standard-cell logic with three external SRAM ports.
export ADDER_MAP_FILE :=
