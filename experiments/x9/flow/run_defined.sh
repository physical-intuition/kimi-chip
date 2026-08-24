#!/usr/bin/env bash
set -euo pipefail
mkdir -p /tmp/x9-build artifacts
iverilog -g2012 -Wall -o /tmp/x9-build/defined \
  rtl/requant_24_to_8.v rtl/weight_addr_gen.v rtl/mac_scheduler.v tb/tb_defined_units.v
vvp /tmp/x9-build/defined
iverilog -g2012 -Wall -o /tmp/x9-build/controller \
  rtl/x8_controller.v tb/tb_x9_controller.v
vvp /tmp/x9-build/controller
iverilog -g2012 -Wall -tnull rtl/*.v
yosys -l artifacts/synth_requant.log flow/synth_requant.ys
yosys -l artifacts/synth_addr.log flow/synth_addr.ys
yosys -l artifacts/synth_scheduler.log flow/synth_scheduler.ys
