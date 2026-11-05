import hashlib
from pathlib import Path
import sys
import tempfile
import unittest
import zipfile
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from rom_inspector import inspect

class ImportTests(unittest.TestCase):
    def test_truncated_rom_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "truncated.gbc"
            path.write_bytes(b"not a ROM")
            with self.assertRaises(ValueError): inspect(path)

    def test_archive_ambiguity_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "multiple.zip"
            with zipfile.ZipFile(path, "w") as archive:
                archive.writestr("one.gbc", bytes(0x150))
                archive.writestr("two.gbc", bytes(0x150))
            with self.assertRaises(ValueError): inspect(path)

    def test_unknown_identity_is_not_compatibility(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "unknown.gbc"
            path.write_bytes(bytes(0x150))
            result = inspect(path)
            self.assertFalse(result["supported_identity"])
            self.assertFalse(result["network_gameplay_verified"])

if __name__ == "__main__": unittest.main()
