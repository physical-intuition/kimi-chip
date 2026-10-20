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

# Use a higher-drive clock tree to reduce insertion delay at constrained outputs.
export CTS_BUF_LIST = BUF_X8 BUF_X16
export CTS_CLUSTER_SIZE = 32

# Preserve the logic/latency and strengthen only debug output launch cells.
export POST_CTS_TCL = ./designs/nangate45/dataflow_top/flow/size_debug.tcl
# Reserve extracted-route margin, including reg-to-reg paths.
export SETUP_SLACK_MARGIN = 0.03
export OPT_POST_GRT_WNS = 1
