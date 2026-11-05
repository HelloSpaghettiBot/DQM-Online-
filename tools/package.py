#!/usr/bin/env python3
"""Create explicit, sanitized public source and native alpha downloads."""
import argparse
import hashlib
import json
import re
from pathlib import Path
import shutil
import stat
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PUBLIC = ROOT / "web/public/downloads"
RELEASE_TEXT = (ROOT / "shared/release.gd").read_text()
BUILD = int(re.search(r"const BUILD = (\d+)", RELEASE_TEXT)[1])
VERSION = re.search(r'const VERSION = "([^"]+)"', RELEASE_TEXT)[1]
BLOCKED_PARTS = {".local", ".tools", ".git", ".godot", "__pycache__", "private", "credentials", "saves", "node_modules"}
BLOCKED_SUFFIXES = {".gb", ".gbc", ".gba", ".sav", ".srm", ".state", ".db", ".sqlite", ".sqlite3", ".log", ".keystore", ".jks", ".pem", ".key", ".p12", ".pfx", ".env", ".pyc"}
COMPILED_SUFFIXES = {".o", ".os", ".a", ".so", ".dll", ".exe", ".apk", ".lib", ".exp", ".zip", ".tpz"}

def safe(path):
    parts = set(path.parts)
    if parts & BLOCKED_PARTS or path.suffix.lower() in BLOCKED_SUFFIXES:
        raise ValueError(f"Private/ROM file cannot be published: {path}")
    if path.name in ("AGENTS.md", "ORIGINAL_BLUEPRINT.md"):
        raise ValueError(f"Private instruction/reference document excluded: {path}")

def add(archive, source, relative):
    safe(relative)
    archive.write(source, relative.as_posix())

def source_files():
    top = ["README.md", "LICENSE", "THIRD_PARTY_NOTICES.md", "DISCLAIMER.md", "CONTRIBUTING.md", "SECURITY.md", ".gitignore"]
    for name in top: yield ROOT / name, Path(name)
    for folder in ("client", "native", "server", "shared", "tools", "web", "deployment", "docs", "tests"):
        for source in sorted((ROOT / folder).rglob("*")):
            if not source.is_file() or source.is_symlink(): continue
            rel = source.relative_to(ROOT)
            if set(rel.parts) & BLOCKED_PARTS or set(rel.parts) & {"bin", "addons"}: continue
            if folder in ("client", "server") and "shared" in rel.parts: continue
            if "downloads" in rel.parts or rel.name == "ORIGINAL_BLUEPRINT.md": continue
            if rel.suffix.lower() in COMPILED_SUFFIXES or rel.name.startswith(".scons"): continue
            safe(rel)
            yield source, rel
    # Complete corresponding patched sources for the GPL emulator bridge.
    for folder in ("gambatte", "godot-cpp"):
        source_root = ROOT / ".vendor" / folder
        for source in sorted(source_root.rglob("*")):
            if not source.is_file() or source.is_symlink(): continue
            rel = source.relative_to(source_root)
            if set(rel.parts) & BLOCKED_PARTS or set(rel.parts) & {"bin", "gen", "obj", "libs"}: continue
            if rel.suffix.lower() in COMPILED_SUFFIXES or rel.name.startswith(".scons"): continue
            safe(rel)
            yield source, Path(".vendor") / folder / rel

def source_archive():
    target = PUBLIC / "DQMOnline-source.zip"
    files = list(source_files())
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for source, relative in files: add(archive, source, Path("DQMOnline") / relative)
    print(f"Source: {len(files)} files; {target.stat().st_size} bytes")
    return target

def native_archive(platform, required):
    folder = ROOT / "builds" / platform.lower()
    for name in required:
        if not (folder / name).is_file(): raise ValueError(f"Missing required native component: {folder / name}")
    target = PUBLIC / f"DQMOnline-{platform.lower()}.zip"
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for source in sorted(folder.iterdir()):
            if not source.is_file(): continue
            add(archive, source, Path("DQMOnline") / source.name)
        for name in ("README.md", "LICENSE", "THIRD_PARTY_NOTICES.md", "DISCLAIMER.md"):
            add(archive, ROOT / name, Path("DQMOnline") / name)
        for source in (ROOT / "docs/licenses").glob("*"):
            add(archive, source, Path("DQMOnline/licenses") / source.name)
        add(archive, ROOT / "client/assets/fonts/OFL.txt", Path("DQMOnline/licenses/VT323-OFL.txt"))
    return target

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-only", action="store_true")
    args = parser.parse_args()
    PUBLIC.mkdir(parents=True, exist_ok=True)
    source_archive()
    if args.source_only: return
    releases = []
    for platform, required, description in [
        ("Windows", ["DQMOnline.exe", "DQMOnline.pck", "gambatte_libretro.dll", "libdqmcore.windows.template_debug.x86_64.dll"], "Windows 10/11 · x64 · exported alpha, device testing pending"),
        ("Linux", ["DQMOnline.x86_64", "DQMOnline.pck", "libgambatte_libretro.so", "libdqmcore.linux.template_debug.x86_64.so"], "Linux x64 · glibc 2.39+ · alpha"),
    ]:
        target = native_archive(platform, required)
        releases.append({"platform": platform, "url": "/DQM/downloads/" + target.name, "description": description,
                         "sha256": hashlib.sha256(target.read_bytes()).hexdigest(), "bytes": target.stat().st_size, "build": BUILD, "version": VERSION})
    apk = ROOT / "builds/DQMOnline-android.apk"
    if not apk.is_file(): raise ValueError("Android APK has not been exported")
    target = PUBLIC / apk.name
    shutil.copy2(apk, target)
    releases.append({"platform": "Android", "url": "/DQM/downloads/" + target.name, "description": "Android 10+ · arm64 · debug alpha, device testing pending",
                     "sha256": hashlib.sha256(target.read_bytes()).hexdigest(), "bytes": target.stat().st_size, "build": BUILD, "version": VERSION})
    (PUBLIC / "manifest.json").write_text(json.dumps(releases, indent=2) + "\n")
    print("Packaged Windows, Linux, Android and source; no local ROMs or private data included.")

if __name__ == "__main__": main()
