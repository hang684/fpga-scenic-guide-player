"""Run deterministic recording RTL tests using a project-local Icarus build."""
import os
import struct
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TESTS = ROOT / "tests"
HDL = ROOT / "src/user_source/hdl_source/advanced_curated"
BIN = ROOT / "tools/hdl_sim/mingw64/bin"
sys.path.insert(0, str(ROOT / "tools"))
from recording_format import make_header


def hex_file(name, data):
    (TESTS / name).write_text("\n".join(f"{b:02x}" for b in data))


def directory_fixture():
    boot = bytearray(512)
    boot[0] = 0xEB
    struct.pack_into("<H", boot, 11, 512)
    boot[13] = 2
    struct.pack_into("<H", boot, 14, 32)
    boot[16] = 1
    struct.pack_into("<I", boot, 32, 200000)
    struct.pack_into("<I", boot, 36, 1)
    struct.pack_into("<I", boot, 44, 2)
    boot[510:] = b"\x55\xaa"
    directory = bytearray(1024)
    names = [(f"PIC{i}    BMP", 3+i, 4096) for i in range(1, 5)]
    names += [(f"AUDIO{i}  PCM", 8+i, 4096) for i in range(1, 5)]
    names += [("FPGA_CFGBIN", 15, 512)]
    names += [(f"REC{i}{bank}   BIN", 20+(i-1)*2+(bank=="B"), 2880512)
              for i in range(1, 5) for bank in "AB"]
    for i, (name, cluster, size) in enumerate(names):
        assert len(name) == 11, name
        base = i*32
        directory[base:base+11] = name.encode("ascii")
        directory[base+11] = 0x20
        struct.pack_into("<H", directory, base+26, cluster)
        struct.pack_into("<I", directory, base+28, size)
    return boot + directory


def main():
    hex_file("header_golden.hex", make_header(2, 1, 0xFFFFFFFF, 12345, 0x89ABCDEF))
    hex_file("scanner_disk.hex", directory_fixture())
    import zlib
    payload_a = bytes((i ^ 0xA6) & 255 for i in range(600))
    payload_b = bytes((i ^ 0x79) & 255 for i in range(200))
    fat = bytearray(512)
    for cluster, link in [(5, 9), (9, 6), (6, 0x0FFFFFFF),
                          (20, 21), (21, 22), (22, 0x0FFFFFFF)]:
        struct.pack_into("<I", fat, cluster*4, link)
    hex_file("manager_card.hex",
             make_header(0, 0, 0xFFFFFFFF, 300, zlib.crc32(payload_a)) + payload_a + bytes(424) +
             make_header(0, 1, 0, 100, zlib.crc32(payload_b)) + payload_b + bytes(824) + fat)
    env = os.environ.copy()
    env["PATH"] = str(BIN) + os.pathsep + env.get("PATH", "")
    cases = {
        "i2s": ["inmp441_i2s_rx"],
        "prefix": ["fat32_file_streamer"],
        "packer": ["record_sector_packer", "record_pcm_fifo"],
        "header": ["record_commit_header"],
        "cursor": ["record_fat_cursor"],
        "verify": ["record_sector_verify"],
        "scanner": ["fat32_volume_scanner"],
        "writer": ["record_file_writer", "record_sector_packer", "record_pcm_fifo",
                   "record_fat_cursor", "record_sector_verify", "record_commit_header",
                   "record_allocation_check"],
    }
    cases["manager"] = ["recording_manager", *cases["writer"]]
    for case, sources in cases.items():
        top = "tb_record_" + case
        output = TESTS / (case + ".vvp")
        subprocess.run([str(BIN / "iverilog.exe"), "-g2012", "-s", top,
                        "-o", str(output), str(TESTS / (top + ".v")),
                        *[str(HDL / (s + ".v")) for s in sources]],
                       cwd=TESTS, env=env, check=True)
        subprocess.run([str(BIN / "vvp.exe"), str(output)],
                       cwd=TESTS, env=env, check=True, timeout=20)
    # Cross-check FPGA-generated header and payload CRC against Python.
    import zlib
    from recording_format import parse_header
    card = bytes(int(line, 16) for line in (TESTS / "writer_card.hex").read_text().splitlines()
                 if line and not line.startswith("//"))
    header = parse_header(card[:512], 0, 0)
    assert header is not None and header["samples"] == 300
    assert header["payload_crc"] == zlib.crc32(card[512:1112])
    print("PASS saved header/payload CRC against Python reference")
    for sys_hz in (62500000, 50000000):
        output = f"i2s_{sys_hz}.vvp"
        subprocess.run([str(BIN / "iverilog.exe"), "-g2012", "-s", "tb_record_i2s",
                        f"-Ptb_record_i2s.SYS_HZ={sys_hz}", "-o", output, "tb_record_i2s.v",
                        str(HDL / "inmp441_i2s_rx.v")], cwd=TESTS, env=env, check=True)
        subprocess.run([str(BIN / "vvp.exe"), output],
                       cwd=TESTS, env=env, check=True, timeout=20)
    subprocess.run([str(BIN / "iverilog.exe"), "-g2012", "-s", "tb_record_packer",
                    "-Ptb_record_packer.AUTOSTOP=1", "-o", "packer_limit.vvp", "tb_record_packer.v",
                    *[str(HDL / (s + ".v")) for s in cases["packer"]]],
                   cwd=TESTS, env=env, check=True)
    subprocess.run([str(BIN / "vvp.exe"), "packer_limit.vvp"],
                   cwd=TESTS, env=env, check=True, timeout=20)
    subprocess.run([str(BIN / "iverilog.exe"), "-g2012", "-s", "tb_record_scanner",
                    "-Ptb_record_scanner.END_WITH_DATA=1", "-o", "scanner_end.vvp", "tb_record_scanner.v",
                    str(HDL / "fat32_volume_scanner.v")], cwd=TESTS, env=env, check=True)
    subprocess.run([str(BIN / "vvp.exe"), "scanner_end.vvp"],
                   cwd=TESTS, env=env, check=True, timeout=20)
    subprocess.run([str(BIN / "iverilog.exe"), "-g2012", "-s", "tb_record_writer",
                    "-Ptb_record_writer.CORRUPT=1", "-o", "writer_failure.vvp",
                    "tb_record_writer.v", *[str(HDL / (s + ".v")) for s in cases["writer"]]],
                   cwd=TESTS, env=env, check=True)
    subprocess.run([str(BIN / "vvp.exe"), "writer_failure.vvp"],
                   cwd=TESTS, env=env, check=True, timeout=20)
    subprocess.run([str(BIN / "iverilog.exe"), "-g2012", "-s", "tb_record_writer",
                    "-Ptb_record_writer.BAD_CHAIN=1", "-o", "writer_bad_chain.vvp",
                    "tb_record_writer.v", *[str(HDL / (s + ".v")) for s in cases["writer"]]],
                   cwd=TESTS, env=env, check=True)
    subprocess.run([str(BIN / "vvp.exe"), "writer_bad_chain.vvp"],
                   cwd=TESTS, env=env, check=True, timeout=20)
    for corrupt in (1, 2):
        subprocess.run([str(BIN / "iverilog.exe"), "-g2012", "-s", "tb_record_manager",
                        f"-Ptb_record_manager.CORRUPT={corrupt}", "-o", "manager_failure.vvp",
                        "tb_record_manager.v", *[str(HDL / (s + ".v")) for s in cases["manager"]]],
                       cwd=TESTS, env=env, check=True)
        subprocess.run([str(BIN / "vvp.exe"), "manager_failure.vvp"],
                       cwd=TESTS, env=env, check=True, timeout=20)
    subprocess.run([str(BIN / "iverilog.exe"), "-g2012", "-s", "tb_record_sd_owner",
                    "-o", "sd_owner.vvp", "tb_record_sd_owner.v", "record_media_stub.v", "record_sd_stub.v",
                    str(ROOT / "src/user_source/hdl_source/SD/sd_card_bmp.v"),
                    *[str(HDL / (s + ".v")) for s in cases["manager"]]],
                   cwd=TESTS, env=env, check=True)
    subprocess.run([str(BIN / "vvp.exe"), "sd_owner.vvp"],
                   cwd=TESTS, env=env, check=True, timeout=20)


if __name__ == "__main__":
    main()
