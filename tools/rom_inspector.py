#!/usr/bin/env python3
"""Inspect a local GB/GBC/GBA ROM or ZIP without uploading or modifying it."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

COBI_SHA = "8e38a7420ef5239c7196aa4fd4b1499e65db2823e875bbf8241bb2199e766d4e"

def inspect(path):
    path = Path(path)
    member = None
    if path.suffix.lower() == ".zip":
        with zipfile.ZipFile(path) as archive:
            entries = [i for i in archive.infolist() if Path(i.filename).suffix.lower() in (".gb", ".gbc", ".gba")]
            if len(entries) != 1:
                raise ValueError("ZIP must contain exactly one GB/GBC/GBA ROM.")
            info = entries[0]
            if info.file_size > 8 * 1024 * 1024:
                raise ValueError("ROM exceeds the import limit.")
            member = info.filename
            data = archive.read(info)
    else:
        if path.stat().st_size > 8 * 1024 * 1024:
            raise ValueError("ROM exceeds the import limit.")
        data = path.read_bytes()
    if len(data) < 0x150:
        raise ValueError("File is too short to contain a Game Boy header.")
    digest = hashlib.sha256(data).hexdigest()
    gba = (member or str(path)).lower().endswith(".gba") or (len(data) >= 0xc0 and data[0xb2] == 0x96 and digest == "fb388539b95fdaf6009bad879e9bbb25955daf8d4d438486a9213d407b2b48ce")
    if gba:
        return {"title": data[0xa0:0xac].split(b"\0")[0].decode("ascii", errors="replace"),
                "game_code": data[0xac:0xb0].decode("ascii", errors="replace"),
                "sha256": digest, "size": len(data), "archive_member": member, "platform": "GBA",
                "header_checksum_valid": (-sum(data[0xa0:0xbd])-0x19)&255 == data[0xbd],
                "recognized_optional_identity": digest == "fb388539b95fdaf6009bad879e9bbb25955daf8d4d438486a9213d407b2b48ce",
                "supported_identity": False, "network_gameplay_verified": False}
    checksum = 0
    for byte in data[0x134:0x14D]:
        checksum = (checksum - byte - 1) & 255
    return {
        "title": data[0x134:0x13F].split(b"\0")[0].decode("ascii", errors="replace"),
        "game_code": data[0x13F:0x143].decode("ascii", errors="replace"),
        "sha256": digest, "size": len(data), "archive_member": member,
        "header_checksum_valid": checksum == data[0x14D],
        "global_checksum_valid": (sum(data[:0x14E]) + sum(data[0x150:])) & 0xFFFF == int.from_bytes(data[0x14E:0x150], "big"),
        "cartridge_type": hex(data[0x147]), "region": data[0x14A],
        "version": data[0x14C], "cgb_flag": hex(data[0x143]),
        "supported_identity": digest == COBI_SHA,
        "platform": "GBC",
        "recognized_optional_identity": digest == "1916208828ce85763d7ca03821eb17cec1a51d55cd80a36bd30a3ea653396a39",
        "network_gameplay_verified": False,
    }

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("rom", type=Path)
    args = parser.parse_args()
    print(json.dumps(inspect(args.rom), indent=2))
