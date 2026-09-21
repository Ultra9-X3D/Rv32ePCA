#!/usr/bin/env python3
"""Run Linux/WSL RTL or zero-delay submitted-netlist tests without changing inputs."""
import argparse
import json
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--gate", action="store_true")
parser.add_argument("--cell-root", type=Path)
args = parser.parse_args()
subprocess.run(["python3", str(root / "scripts/check_hashes.py")], check=True)
build = root / "build"
build.mkdir(exist_ok=True)
mode = "gate" if args.gate else "rtl"
obj = build / (mode + "_obj")
flags = []
if args.gate:
    if args.cell_root is None:
        parser.error("--gate requires --cell-root")
    sources = [root / "tests/GateRegressionTb.v", root / "tests/GateDut.v",
               root / "tests/physical_only.v", root / "submission/pca_sta.v"]
    record = {}
    for suffix in ("R", "L"):
        name = "ics55_LLSC_H7C" + suffix
        original = args.cell_root / name / "verilog" / (name + ".v")
        text = original.read_text()
        text, count = re.subn(
            r"udp_mux2 u0\(Y, A, B, S0\);\s*not\s+u1\(Y, Y\);",
            "wire audit_mux_value;\n  udp_mux2 u0(audit_mux_value, A, B, S0);\n"
            "  not u1(Y, audit_mux_value);", text)
        if count != 7:
            raise SystemExit(f"Unexpected library version: {name} has {count} matching MUXI2 models; inspect before using")
        patched = build / (name + "_simulation_patch.v")
        patched.write_text(text)
        sources.append(patched)
        record[name] = {"source": str(original), "patched_models": count}
    (build / "model_patch_record.json").write_text(json.dumps(record, indent=2))
    flags = ["-Dfunctional"]
    marker = "WS2 GATE FUNCTIONAL PASS"
else:
    wrapper = build / "UserDesignDut.v"
    wrapper.write_text("module UserDesignDut #(parameter IO_WIDTH=66)(input clock,reset,"
                       "input [IO_WIDTH-1:0] io_in, output [IO_WIDTH-1:0] io_out,io_oe);\n"
                       "Rv32ePca #(.IO_WIDTH(IO_WIDTH)) dut(.clock(clock),.reset(reset),"
                       ".io_in(io_in),.io_out(io_out),.io_oe(io_oe));\nendmodule\n")
    sources = [root / "tests/Rv32ePcaTb.v", wrapper] + sorted((root / "rtl").glob("*.v"))
    marker = "RV32E PCA UNIT TEST PASS"
cmd = ["verilator", "--binary", "--timing", "--assert", "-j", "4", "-Wno-fatal",
       "--top-module", "Rv32ePcaTb", "--Mdir", str(obj)] + flags + list(map(str, sources))
with (build / (mode + "_build.log")).open("w") as log:
    result = subprocess.run(cmd, cwd=root, stdout=log, stderr=subprocess.STDOUT)
if result.returncode:
    raise SystemExit(f"Build failed; see build/{mode}_build.log")
result = subprocess.run([str(obj / "VRv32ePcaTb")], cwd=root, stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT, text=True, timeout=120)
(build / (mode + "_run.log")).write_text(result.stdout)
print(result.stdout)
if result.returncode or marker not in result.stdout:
    raise SystemExit("Simulation failed")
