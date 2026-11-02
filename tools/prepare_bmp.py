"""Convert images to the fixed-size BMP files accepted by the FPGA player."""

import argparse
import shutil
import struct
import subprocess
from pathlib import Path


def check_bmp(path: Path, width: int, height: int) -> None:
    expected_size = 54 + width * height * 3
    with path.open("rb") as bitmap:
        header = bitmap.read(54)
    if (
        len(header) != 54
        or header[:2] != b"BM"
        or path.stat().st_size != expected_size
        or struct.unpack_from("<I", header, 2)[0] != expected_size
        or struct.unpack_from("<I", header, 10)[0] != 54
        or struct.unpack_from("<I", header, 14)[0] != 40
        or struct.unpack_from("<ii", header, 18) != (width, height)
        or struct.unpack_from("<H", header, 26)[0] != 1
        or struct.unpack_from("<H", header, 28)[0] != 24
        or struct.unpack_from("<I", header, 30)[0] != 0
    ):
        raise ValueError(f"Unsupported BMP output: {path}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("images", nargs=4, type=Path, help="Images in PIC1..PIC4 order")
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--mode", choices=("crop", "letterbox"), default="crop")
    parser.add_argument("--size", choices=("640x480", "1280x960"), default="640x480")
    parser.add_argument("--ffmpeg", default=shutil.which("ffmpeg"), help="FFmpeg executable")
    args = parser.parse_args()
    if not args.ffmpeg:
        parser.error("FFmpeg not found; supply --ffmpeg PATH")
    for image in args.images:
        if not image.is_file():
            parser.error(f"Missing image: {image}")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    width, height = (int(value) for value in args.size.split("x"))
    if args.mode == "crop":
        filters = (f"scale={width}:{height}:flags=bilinear:"
                   f"force_original_aspect_ratio=increase,crop={width}:{height}")
    else:
        filters = (f"scale={width}:{height}:flags=bilinear:"
                   f"force_original_aspect_ratio=decrease,"
                   f"pad={width}:{height}:(ow-iw)/2:(oh-ih)/2:black")
    for number, image in enumerate(args.images, start=1):
        output = args.output_dir / f"PIC{number}.BMP"
        subprocess.run(
            [args.ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", str(image),
             "-vf", filters, "-frames:v", "1", "-c:v", "bmp", "-pix_fmt", "bgr24", str(output)],
            check=True,
        )
        check_bmp(output, width, height)
        print(f"{image} -> {output} ({width}x{height}, 24-bit BMP)")


if __name__ == "__main__":
    main()
