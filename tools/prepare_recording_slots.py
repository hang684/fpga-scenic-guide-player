"""Create reserved A/B recording files on an existing FAT32 card.

Never format a card or overwrite existing recordings. Each slot reserves a
512-byte commit header followed by 30 seconds of 48 kHz mono signed PCM16.
The files are storage containers, not directly playable WAV files.
"""
import argparse
import json
import os
import shutil
from pathlib import Path

SAMPLE_RATE = 48000
MAX_SECONDS = 30
HEADER_BYTES = 512
SLOT_BYTES = HEADER_BYTES + SAMPLE_RATE * MAX_SECONDS * 2


def prepare(root: Path):
    if not root.is_dir():
        raise ValueError(f"Directory does not exist: {root}")
    result = []
    paths = [root / f"REC{picture}{bank}.BIN"
             for picture in range(1, 5) for bank in "AB"]
    for path in paths:
        if path.exists() and (not path.is_file() or path.stat().st_size != SLOT_BYTES):
            raise ValueError(f"Existing slot has unexpected length; preserved: {path}")
    required = sum(SLOT_BYTES for path in paths if not path.exists())
    if shutil.disk_usage(root).free < required:
        raise ValueError(f"Insufficient free space; need {required} bytes")
    for picture in range(1, 5):
        for bank in "AB":
            path = root / f"REC{picture}{bank}.BIN"
            if path.exists():
                if path.stat().st_size != SLOT_BYTES:
                    raise ValueError(f"Existing slot has unexpected length; preserved: {path}")
                result.append({"file": path.name, "status": "preserved"})
                continue
            # Exclusive creation prevents overwriting an existing recording.
            try:
                with path.open("xb") as stream:
                    remaining = SLOT_BYTES
                    block = bytes(65536)
                    while remaining:
                        n = min(remaining, len(block))
                        stream.write(block[:n])
                        remaining -= n
                    stream.flush()
                    os.fsync(stream.fileno())
                if path.stat().st_size != SLOT_BYTES:
                    raise IOError(f"Incomplete slot: {path}")
            except BaseException:
                # Keep a partial file visible for diagnosis; never silently erase.
                raise
            result.append({"file": path.name, "status": "created"})
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("card_root", type=Path, help="TF card root, for example E:/")
    args = parser.parse_args()
    result = prepare(args.card_root)
    print(json.dumps({"sample_rate": SAMPLE_RATE, "seconds_per_slot": MAX_SECONDS,
                      "bytes_per_slot": SLOT_BYTES, "files": result}, indent=2))
    print("Reserved files created. Safely eject the card. Recorder firmware is required.")


if __name__ == "__main__":
    main()
