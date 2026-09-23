export DESIGN_NAME = dataflow_top
export PLATFORM    = nangate45
export VERILOG_FILES = $(sort $(wildcard ./designs/$(PLATFORM)/$(DESIGN_NAME)/*.v))
export SDC_FILE      = ./designs/$(PLATFORM)/$(DESIGN_NAME)/constraint.sdc
export ABC_AREA = 1
export CORE_UTILIZATION = 40
export PLACE_DENSITY = 0.60
