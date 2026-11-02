#!/usr/bin/env python3
"""Convert 16-bit PCM WAV audio to the FPGA's raw mono 48 kHz format."""

import argparse
import array
import sys
import wave
from pathlib import Path


TARGET_RATE = 48_000
CHUNK_FRAMES = 16_384


def read_mono_samples(source: wave.Wave_read) -> array.array:
    channels = source.getnchannels()
    sample_width = source.getsampwidth()
    if channels not in (1, 2):
        raise ValueError(f"expected mono or stereo WAV, got {channels} channels")
    if sample_width != 2:
        raise ValueError(f"expected 16-bit PCM WAV, got {sample_width * 8}-bit")
    if source.getcomptype() != "NONE":
        raise ValueError(f"compressed WAV is not supported: {source.getcomptype()}")

    mono = array.array("h")
    while True:
        raw = source.readframes(CHUNK_FRAMES)
        if not raw:
            break
        samples = array.array("h")
        samples.frombytes(raw)
        if sys.byteorder != "little":
            samples.byteswap()
        if channels == 1:
            mono.extend(samples)
        else:
            mono.extend(
                int((samples[index] + samples[index + 1]) / 2)
                for index in range(0, len(samples) - 1, 2)
            )
    return mono


def convert(input_path: Path, output_path: Path) -> int:
    with wave.open(str(input_path), "rb") as source:
        source_rate = source.getframerate()
        if source_rate <= 0:
            raise ValueError("invalid WAV sample rate")
        mono = read_mono_samples(source)

    if not mono:
        raise ValueError("WAV contains no audio samples")

    output_count = max(1, round(len(mono) * TARGET_RATE / source_rate))
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("wb") as output_file:
        output_chunk = array.array("h")
        for output_index in range(output_count):
            source_position = output_index * source_rate / TARGET_RATE
            left_index = min(int(source_position), len(mono) - 1)
            right_index = min(left_index + 1, len(mono) - 1)
            fraction = source_position - left_index
            interpolated = mono[left_index] + (mono[right_index] - mono[left_index]) * fraction
            output_chunk.append(max(-32768, min(32767, int(interpolated))))
            if len(output_chunk) >= CHUNK_FRAMES:
                if sys.byteorder != "little":
                    output_chunk.byteswap()
                output_file.write(output_chunk.tobytes())
                output_chunk = array.array("h")
        if output_chunk:
            if sys.byteorder != "little":
                output_chunk.byteswap()
            output_file.write(output_chunk.tobytes())

    return output_count


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Convert 16-bit PCM WAV to mono signed 16-bit little-endian 48 kHz PCM."
    )
    parser.add_argument("input_wav", type=Path, help="source WAV file")
    parser.add_argument(
        "output_pcm",
        type=Path,
        nargs="?",
        help="output file (default: AUDIO.PCM beside the WAV)",
    )
    args = parser.parse_args()
    output_path = args.output_pcm or args.input_wav.with_name("AUDIO.PCM")
    try:
        sample_count = convert(args.input_wav, output_path)
    except (OSError, wave.Error, ValueError) as error:
        parser.error(str(error))
    duration = sample_count / TARGET_RATE
    print(f"Wrote {output_path} ({sample_count} samples, {duration:.2f} s, 48 kHz mono PCM)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
