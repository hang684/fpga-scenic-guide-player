"""Simulate the standalone INMP441 bring-up image with the project-local Icarus build."""
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TESTS = ROOT / "tests"
HDL = ROOT / "src/user_source/hdl_source"
BIN = ROOT / "tools/hdl_sim/mingw64/bin"

SOURCES = [
    HDL / "reset_sync.v",
    HDL / "SD/seg_decoder.v",
    HDL / "SD/seg_scan.v",
    HDL / "advanced_curated/inmp441_i2s_rx.v",
    HDL / "mic_debug/mic_debug_stats.v",
    HDL / "mic_debug/mic_debug_top.v",
]

if __name__ == "__main__":
    env = os.environ.copy()
    env["PATH"] = str(BIN) + os.pathsep + env.get("PATH", "")
    output = TESTS / "mic_debug.vvp"
    subprocess.run([str(BIN / "iverilog.exe"), "-g2012", "-s", "tb_mic_debug",
                    "-o", str(output), str(TESTS / "tb_mic_debug.v"), *map(str, SOURCES)],
                   cwd=TESTS, env=env, check=True)
    result = subprocess.run([str(BIN / "vvp.exe"), str(output)], cwd=TESTS, env=env,
                            check=True, timeout=120, capture_output=True, text=True)
    print(result.stdout, end="")
    if "PASS mic_debug" not in result.stdout:
        raise SystemExit(1)
