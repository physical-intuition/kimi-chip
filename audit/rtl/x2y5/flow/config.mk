export DESIGN_NAME = audit_top
export PLATFORM = nangate45

AUDIT_RTL = /src
export VERILOG_FILES = $(AUDIT_RTL)/audit_top.v $(AUDIT_RTL)/layer_controller.v $(AUDIT_RTL)/kda_state_sram.v $(AUDIT_RTL)/mla_kv_cache.v $(AUDIT_RTL)/conv_history.v

export SDC_FILE = $(dir $(DESIGN_CONFIG))constraint.sdc

export CORE_UTILIZATION = 25
export PLACE_DENSITY_LB_ADDON = 0.05
export TNS_END_PERCENT = 100
export CTS_BUF_DISTANCE = 60
export ABC_DRIVER_CELL = BUF_X1
export ABC_LOAD_IN_FF = 5
