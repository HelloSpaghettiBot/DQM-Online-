#!/usr/bin/env python3
"""Fetch pinned, checksum-verified dependencies; build the native Linux client."""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import urllib.request
import zipfile
ROOT = Path(__file__).resolve().parents[1]
GAMBATTE = "77f2567d718b8973d02caa2daa8dce4953faf811"
GODOT_CPP = "27d9dd23c83871e0619fca5dc2cddfbfd69e926a"
FILES = [
    ("Godot_v4.6.3-stable_linux.x86_64.zip", "https://github.com/godotengine/godot-builds/releases/download/4.6.3-stable/Godot_v4.6.3-stable_linux.x86_64.zip", "d0bc2113065e481c9c2c2b2c37daa4e8be3fe9e27f0ab9ab0b6096e9a37907f3"),
    ("dqmonline-gambatte-77f2567.tar.gz", f"https://github.com/libretro/gambatte-libretro/archive/{GAMBATTE}.tar.gz", "45e63bc79390093b78de025172ea289ded139f4ecf1e8072242f34d7dd540338"),
    ("dqmonline-godot-cpp-27d9dd2.tar.gz", f"https://github.com/godotengine/godot-cpp/archive/{GODOT_CPP}.tar.gz", "c01332c0bc2444ca21da647be481eff5bf4dfa969351f51cc6bbf559b9512d84"),
    ("dqmonline-godot-sqlite-v4.8.zip", "https://github.com/2shady4u/godot-sqlite/releases/download/v4.8/addons.zip", "f81531b5b9f1d4f422e9f882c409701adf197a17f894ca65ee2fa25759c25270"),
]

def run(*command, cwd=ROOT):
    print("Running:", " ".join(map(str, command)), flush=True)
    subprocess.run(list(map(str, command)), cwd=cwd, check=True)

def unpack_tar(path, destination):
    if destination.exists(): return
    destination.mkdir(parents=True)
    with tarfile.open(path) as archive:
        for info in archive.getmembers():
            pieces = Path(info.name).parts[1:]
            if not pieces: continue
            if info.issym() or info.islnk(): continue
            info.name = str(Path(*pieces))
            archive.extract(info, destination, filter="data")

def patch_core():
    folder = ROOT / ".vendor/gambatte"
    source = folder / "libgambatte/libretro/libretro.cpp"
    code = source.read_text()
    if "static DqmSerial dqm_serial;" not in code:
        code = code.replace('#include "gambatte.h"', '#include "gambatte.h"\n#include "dqm_serial.h"')
        code = code.replace('static gambatte::GB gb;', '''static gambatte::GB gb;
static DqmSerial dqm_serial;
extern "C" {
RETRO_API void retro_dqm_link_enable(bool value) { dqm_serial.enable(value); }
RETRO_API void retro_dqm_link_attach(bool value) { gb.setSerialIO(value ? &dqm_serial : NULL); }
RETRO_API void retro_dqm_link_push(const uint8_t *data, int length) {
  for (int i = 0; i + 1 < length; i += 2) dqm_serial.push(data[i], data[i + 1]);
}
RETRO_API int retro_dqm_link_poll(uint8_t *data, int length) { return dqm_serial.poll(data, length); }
}
''')
        source.write_text(code)
    shutil.copy2(ROOT / "native/patches/dqm_serial.h", source.with_name("dqm_serial.h"))
    makefile = folder / "Makefile.libretro"
    makefile.write_text(makefile.read_text().replace("-std=c++98", "-std=c++17"))
    memory = folder / "libgambatte/src/gambatte-memory.cpp"
    code = memory.read_text()
    # Upstream network serial re-read the most significant input bits on each
    # intermediate SC/SB read. Preserve timing, consume each input bit once.
    code = code.replace("(serialize_value_ >> (8 - serialCnt_))", "(serialize_value_ & ((1u << serialCnt_) - 1u))")
    code = code.replace("(serialize_value_ >> (8 - (serialCnt_ - targetCnt)))", "((serialize_value_ >> targetCnt) & ((1u << (serialCnt_ - targetCnt)) - 1u))")
    memory.write_text(code)
    import importlib.util
    spec = importlib.util.spec_from_file_location("appearance_patch", ROOT / "native/patches/apply_appearance.py")
    appearance_patch = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(appearance_patch)
    appearance_patch.patch(folder, ROOT)
    # GPL-2.0 section 2(a): identify the modified upstream files and date.
    changes = {
        "libgambatte/libretro/libretro.cpp": "bounded DQM cable bridge",
        "libgambatte/src/gambatte-memory.cpp": "consume incoming serial bits once",
        "Makefile.libretro": "C++17 build for the DQM bridge",
    }
    for relative, description in changes.items():
        path = folder / relative
        text = path.read_text()
        if "DQM Online modification" not in text:
            prefix = "#" if path.name.startswith("Makefile") else "//"
            path.write_text(f"{prefix} DQM Online modification, 2026-11-05: {description}.\n" + text)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--downloads", type=Path, default=Path("/run/media/system/Files/Downloads"))
    parser.add_argument("--jobs", type=int, default=4)
    args = parser.parse_args()
    if str(args.downloads).startswith("/run/media/system/Files/"):
        mounted = subprocess.check_output(["findmnt", "-n", "-o", "TARGET", "-T", "/run/media/system/Files"], text=True).strip()
        if mounted != "/run/media/system/Files": raise SystemExit("Mount the FILES drive before downloading.")
    args.downloads.mkdir(parents=True, exist_ok=True)
    for name, url, checksum in FILES:
        target = args.downloads / name
        if not target.exists():
            print("Downloading", name, flush=True)
            temporary = target.with_suffix(target.suffix + ".part")
            urllib.request.urlretrieve(url, temporary)
            temporary.replace(target)
        if hashlib.sha256(target.read_bytes()).hexdigest() != checksum:
            raise SystemExit(f"Checksum mismatch: {target}")
    (ROOT / ".tools").mkdir(exist_ok=True)
    with zipfile.ZipFile(args.downloads / FILES[0][0]) as archive:
        archive.extractall(ROOT / ".tools")
    engine = ROOT / ".tools/Godot_v4.6.3-stable_linux.x86_64"
    engine.chmod(0o755)
    unpack_tar(args.downloads / FILES[1][0], ROOT / ".vendor/gambatte")
    unpack_tar(args.downloads / FILES[2][0], ROOT / ".vendor/godot-cpp")
    godot_cpp_source = ROOT / ".vendor/godot-cpp/src/godot.cpp"
    code = godot_cpp_source.read_text()
    if "#include <cstdlib>" not in code:
        godot_cpp_source.write_text("#include <cstdlib>\n" + code)
    with zipfile.ZipFile(args.downloads / FILES[3][0]) as archive:
        archive.extractall(ROOT / "server")
    venv = ROOT / ".tools/venv"
    if not venv.exists(): run("python3", "-m", "venv", venv)
    run(venv / "bin/python", "-m", "pip", "install", "scons==4.11.1")
    patch_core()
    run("make", "-f", "Makefile.libretro", f"-j{args.jobs}", "platform=unix", cwd=ROOT / ".vendor/gambatte")
    (ROOT / "client/bin").mkdir(exist_ok=True)
    shutil.copy2(ROOT / ".vendor/gambatte/gambatte_libretro.so", ROOT / "client/bin/libgambatte_libretro.so")
    run(venv / "bin/scons", "-C", "native", "platform=linux", "target=template_debug", "build_profile=build_profile.json", "use_static_cpp=no", f"-j{args.jobs}")
    from run import prepare
    prepare()
    for project in ("server", "client"):
        run(engine, "--headless", "--editor", "--path", ROOT / project, "--import")
    print("Bootstrap complete. No ROMs were downloaded or packaged.")

if __name__ == "__main__": main()
