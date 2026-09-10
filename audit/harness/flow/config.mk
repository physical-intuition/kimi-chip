# OpenROAD Flow Config for kimi-chip audit
# Based on experiments/x5/flow/config_y4.mk

export DESIGN_NAME = audit_top
export PLATFORM = nangate45

# RTL sources - all audit modules
AUDIT_RTL_DIR = $(dir $(DESIGN_CONFIG))../../rtl
export VERILOG_FILES = \
    $(AUDIT_RTL_DIR)/audit_top.v \
    $(AUDIT_RTL_DIR)/layer_controller.v \
    $(AUDIT_RTL_DIR)/kda_state_sram.v \
    $(AUDIT_RTL_DIR)/mla_kv_cache.v \
    $(AUDIT_RTL_DIR)/conv_history.v

# Constraints
export SDC_FILE = $(dir $(DESIGN_CONFIG))constraint.sdc

# Floorplan
export CORE_UTILIZATION = 25
export PLACE_DENSITY_LB_ADDON = 0.05

# Routing
export DETAILED_ROUTE_ARGS = -droute_end_iter 8

# Timing
export TNS_END_PERCENT = 100

# CTS
export CTS_BUF_DISTANCE = 60

# Platform-specific (Nangate45)
export ABC_DRIVER_CELL = BUF_X1
export ABC_LOAD_IN_FF = 5

# Results - will be overridden by run_iteration.py
# export RESULTS_DIR = ...
