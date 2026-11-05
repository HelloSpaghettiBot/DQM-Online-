#!/usr/bin/env python3
"""Run the pinned Godot client/server from any working directory."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
from accounts import demo

ROOT = Path(__file__).resolve().parents[1]

def prepare():
    for project in ("client", "server"):
        dest = ROOT / project / "shared"
        dest.mkdir(exist_ok=True)
        for source in (ROOT / "shared").glob("*.gd"):
            shutil.copy2(source, dest / source.name)

def godot():
    engine = os.environ.get("GODOT") or str(ROOT / ".tools/Godot_v4.6.3-stable_linux.x86_64")
    if not Path(engine).is_file():
        engine = shutil.which("godot") or shutil.which("godot4")
    if not engine:
        raise SystemExit("Godot 4.6.3 is missing. Set GODOT or run tools/bootstrap.py.")
    version = subprocess.check_output([engine, "--version"], text=True).strip()
    if not version.startswith("4.6.3.stable"):
        raise SystemExit(f"Expected Godot 4.6.3 stable, got {version}.")
    return engine

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("component", choices=("client", "server", "editor"))
    parser.add_argument("--dev", action="store_true", help="Provision local accounts; server stays on loopback.")
    parser.add_argument("--dev-account", choices=("alice", "bob"))
    parser.add_argument("--rom", type=Path)
    parser.add_argument("--host", default="403world.com")
    parser.add_argument("--bind", default="127.0.0.1")
    parser.add_argument("--port", default=24778, type=int)
    parser.add_argument("--database", type=Path, default=ROOT / ".local/dqmonline.db")
    parser.add_argument("--profile", default="default")
    parser.add_argument("--connect", action="store_true")
    args = parser.parse_args()
    if args.dev_account and args.host == "403world.com": args.host = "127.0.0.1"
    os.umask(0o077)
    prepare()
    engine = godot()
    if args.dev:
        if args.bind != "127.0.0.1":
            parser.error("Development accounts require a loopback server.")
        demo(args.database, ROOT / ".local/dev_accounts.json")
    project = "server" if args.component == "server" else "client"
    subprocess.run([engine, "--headless", "--editor", "--path", str(ROOT / project), "--import"], check=True)
    command = [engine, "--path", str(ROOT / project)]
    if args.component == "server":
        command += ["--headless", "--", f"--db={args.database.resolve()}", f"--bind={args.bind}", f"--port={args.port}"]
    elif args.component == "editor":
        command += ["--editor"]
    else:
        command += ["--", f"--profile={args.dev_account or args.profile}", f"--host={args.host}", f"--port={args.port}", f"--save-root={ROOT / '.local/profiles'}"]
        if args.rom: command += [f"--rom={args.rom.resolve()}"]
        if args.connect: command += ["--connect"]
        if args.dev_account:
            command += [f"--dev-account={args.dev_account}", f"--credentials={ROOT / '.local/dev_accounts.json'}"]
    raise SystemExit(subprocess.call(command))
