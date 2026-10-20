export DESIGN_NAME = dataflow_top
export PLATFORM    = nangate45
export VERILOG_FILES = $(sort $(wildcard ./designs/$(PLATFORM)/$(DESIGN_NAME)/*.v))
export SDC_FILE      = ./designs/$(PLATFORM)/$(DESIGN_NAME)/constraint.sdc
export ABC_AREA = 0
export CORE_UTILIZATION = 40
export PLACE_DENSITY = 0.60

export ADDITIONAL_LEFS = /OpenROAD-flow-scripts/flow/platforms/nangate45/lef/fakeram45_512x64.lef
export ADDITIONAL_LIBS = /OpenROAD-flow-scripts/flow/platforms/nangate45/lib/fakeram45_512x64.lib

# Leave capacitance/slew headroom for extracted-route parasitics.
export CAP_MARGIN = 10
export SLEW_MARGIN = 10
