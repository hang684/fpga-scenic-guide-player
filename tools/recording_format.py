"""On-card recording format shared with record_commit_header.v.

512-byte header followed by little-endian signed PCM16, 48000 Hz mono.
Header is committed last, after payload verification. Zero headers are invalid.
CRC32 uses the standard reflected IEEE polynomial (same as zlib.crc32).
"""
import struct
import zlib

MAX_SAMPLES = 1_440_000
HEADER_BYTES = 512


def make_header(image, bank, generation, samples, payload_crc):
    if image not in range(4) or bank not in range(2):
        raise ValueError("Invalid image/bank")
    if not 0 < samples <= MAX_SAMPLES:
        raise ValueError("Invalid sample count")
    prefix = struct.pack("<4sBBBBIIIII", b"RPCM", 1, image, bank, 0xA5,
                         generation & 0xFFFFFFFF, samples, 48000,
                         payload_crc & 0xFFFFFFFF, 0)
    return prefix + struct.pack("<I", zlib.crc32(prefix)) + bytes(480)


def parse_header(data, image, bank):
    if len(data) != HEADER_BYTES:
        return None
    magic, version, pic, slot, committed, generation, samples, rate, crc, reserved = \
        struct.unpack("<4sBBBBIIIII", data[:28])
    if (magic != b"RPCM" or version != 1 or pic != image or slot != bank or
            committed != 0xA5 or rate != 48000 or reserved != 0 or
            not 0 < samples <= MAX_SAMPLES or
            struct.unpack("<I", data[28:32])[0] != zlib.crc32(data[:28])):
        return None
    return {"generation": generation, "samples": samples, "payload_crc": crc}


def generation_newer(a, b):
    """Wrap-safe ordering; valid generations differ by fewer than 2**31 takes."""
    return 0 < ((a - b) & 0xFFFFFFFF) < 0x80000000
