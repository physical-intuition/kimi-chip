#!/usr/bin/env python3
import hashlib
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
MANIFEST = pathlib.Path(__file__).with_name("manifest_y3.json")


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    manifest = json.loads(MANIFEST.read_text())
    for rel, expected in manifest["locked_files"].items():
        path = ROOT / rel
        actual = sha256(path)
        if actual != expected:
            print(f"LOCK FAIL {rel}: expected {expected}, got {actual}")
            return 1
    build = ROOT / "experiments/x3/build"
    build.mkdir(parents=True, exist_ok=True)
    out = build / "tb_x3_y3"
    compile_cmd = [
        "iverilog", "-g2012", "-Wall", "-s", "tb_x3_y3", "-o", str(out),
        str(ROOT / "experiments/x1/rtl/x1_y5_kimi.v"),
        str(ROOT / "experiments/x3/rtl/x3_y3_kimi.v"),
        str(ROOT / "experiments/x3/tb/tb_x3_y3.v"),
    ]
    subprocess.run(compile_cmd, check=True)
    sim = subprocess.run(["vvp", str(out)], check=False, text=True, capture_output=True)
    sys.stdout.write(sim.stdout)
    sys.stderr.write(sim.stderr)
    expected_line = manifest["required_transcript"]
    if sim.returncode != 0 or expected_line not in sim.stdout:
        print("LOCK FAIL simulation transcript or return code")
        return 1
    print("LOCK PASS: sparse lane-identity testbench hash and required 768-output transcript match")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
