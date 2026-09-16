export DESIGN_NAME = audit_top
export PLATFORM = nangate45

export VERILOG_FILES = $(DESIGN_DIR)/audit_top.v $(DESIGN_DIR)/layer_controller.v $(DESIGN_DIR)/kda_state_sram.v $(DESIGN_DIR)/mla_kv_cache.v $(DESIGN_DIR)/conv_history.v $(DESIGN_DIR)/fakeram45_256x32.v

export SDC_FILE = $(DESIGN_DIR)/constraint.sdc

export CORE_UTILIZATION = 25
export PLACE_DENSITY_LB_ADDON = 0.05
export TNS_END_PERCENT = 100
export CTS_BUF_DISTANCE = 60
export ABC_DRIVER_CELL = BUF_X1
export ABC_LOAD_IN_FF = 5
