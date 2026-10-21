# X4Y2 bounded traversal
Read CORRECTNESS.md first. This iteration fixes two proven bounds errors and
adds full-cache backpressure; it does not implement missing inference math.

Run:
    bash tests/run.sh
    iverilog -g2012 -s tb_bounds -o /tmp/x4y2-bounds dataflow_top.v kv_banked_2048x64.v tests/fakeram_model.v tests/tb_bounds.v
    vvp /tmp/x4y2-bounds
    python3 -m unittest -v test_golden.py
    bash run.sh --diagnostic --report result.json

Without --diagnostic the golden runner intentionally exits 2. Its arithmetic
model is trace-driven and cannot prove operand selection or missing operators.
