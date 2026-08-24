export DESIGN_NAME = x1_y4_kimi
export PLATFORM = nangate45

export VERILOG_FILES = /home/kit/kimi-chip/experiments/x1/rtl/x1_y3_kimi.v \
                       /home/kit/kimi-chip/experiments/x1/rtl/x1_y4_kimi.v
export SDC_FILE = /home/kit/kimi-chip/experiments/x1/flow/constraint_y4.sdc

# Y3 reached final timing/DRC closure at 20% utilization, but extraction
# exposed 16 max-cap violations that global-route RC had underestimated.
# Preserve its floorplan and timing target, while over-fixing capacitance by
# 20% during placement and post-global-route repair. Y3's worst extracted
# overrun was 12.7%, so this leaves useful model-error margin without an RTL
# topology change or a larger core.
export CORE_UTILIZATION = 20
export PLACE_DENSITY_LB_ADDON = 0.05
export TNS_END_PERCENT = 100
export SYNTH_REPEATABLE_BUILD = 1
export ABC_CLOCK_PERIOD_IN_PS = 2500
export GPL_ROUTABILITY_DRIVEN = 1
export GRT_ALLOW_CONGESTION = 0
export CAP_MARGIN = 20
export NUM_CORES = 4

export ADDER_MAP_FILE :=
