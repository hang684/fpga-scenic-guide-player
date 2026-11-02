import tempfile
import unittest
import zlib
from pathlib import Path
from prepare_recording_slots import prepare, SLOT_BYTES
from recording_format import make_header, parse_header, generation_newer


class StorageTests(unittest.TestCase):
    def test_header_corruption_and_identity(self):
        header = make_header(2, 1, 0xFFFFFFFF, 12345, 0x89ABCDEF)
        self.assertEqual(len(header), 512)
        self.assertEqual(parse_header(header, 2, 1),
                         dict(generation=0xFFFFFFFF, samples=12345, payload_crc=0x89ABCDEF))
        self.assertIsNone(parse_header(header, 1, 1))
        self.assertIsNone(parse_header(header, 2, 0))
        self.assertIsNone(parse_header(bytes(512), 2, 1))
        for offset in range(32):
            bad = bytearray(header)
            bad[offset] ^= 1
            self.assertIsNone(parse_header(bad, 2, 1), offset)
        self.assertTrue(generation_newer(0, 0xFFFFFFFF))
        self.assertFalse(generation_newer(0xFFFFFFFF, 0))
        self.assertFalse(generation_newer(4, 4))
        self.assertEqual(zlib.crc32(b"123456789"), 0xCBF43926)

    def test_prepare_preserves_recordings(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.assertEqual(len(prepare(root)), 8)
            self.assertTrue(all(p.stat().st_size == SLOT_BYTES for p in root.iterdir()))
            recording = root / "REC1A.BIN"
            marker = make_header(0, 0, 7, 256, 123)
            with recording.open("r+b") as stream:
                stream.write(marker)
            self.assertTrue(all(r["status"] == "preserved" for r in prepare(root)))
            with recording.open("rb") as stream:
                self.assertEqual(stream.read(512), marker)

    def test_invalid_existing_file_prevents_creation(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bad = root / "REC4B.BIN"
            bad.write_bytes(b"preserve")
            with self.assertRaises(ValueError):
                prepare(root)
            self.assertEqual(list(root.iterdir()), [bad])
            self.assertEqual(bad.read_bytes(), b"preserve")


if __name__ == "__main__":
    unittest.main()
