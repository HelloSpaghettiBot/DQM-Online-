#!/usr/bin/env python3
"""Two real ENet clients + SQLite server. Synthetic cable bytes, no gameplay claim."""
import argparse
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from accounts import demo
from run import godot, prepare

def run(probe="network_probe.gd"):
    prepare()
    engine = godot()
    with tempfile.TemporaryDirectory(prefix="network-", dir=ROOT / ".local") as directory:
        directory = Path(directory)
        database = directory / "test.db"
        credentials = directory / "credentials.json"
        demo(database, credentials)
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as reservation:
            reservation.bind(("127.0.0.1", 0))
            port = reservation.getsockname()[1]
        log_path = directory / "server.log"
        clients = []
        with log_path.open("w") as log:
            server = subprocess.Popen([engine, "--headless", "--path", str(ROOT / "server"), "--", f"--db={database}", f"--port={port}"], stdout=log, stderr=log)
            try:
                deadline = time.monotonic() + 10
                while time.monotonic() < deadline:
                    if '"listening"' in log_path.read_text(): break
                    if server.poll() is not None: raise RuntimeError(log_path.read_text())
                    time.sleep(0.1)
                else: raise RuntimeError("Server startup timed out")
                for account in ("alice", "bob"):
                    clients.append(subprocess.Popen([engine, "--headless", "--path", str(ROOT / "client"), "--script", str(ROOT / "tests" / probe), "--", f"--account={account}", f"--credentials={credentials}", f"--port={port}"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True))
                results = [client.communicate(timeout=30)[0] for client in clients]
                for output in results: print(output)
                for client in clients:
                    if client.returncode: raise RuntimeError("Network integration failed")
                print("PASS: " + ("emulated GBC serial hardware through authenticated ENet relay" if probe == "cable_probe.gd" else "two authenticated clients, roster, bidirectional plain-text chat, consented link relay, isolated durable server saves, reload, and stale save rejection"))
            finally:
                for client in clients:
                    if client.poll() is None: client.kill(); client.wait()
                server.terminate()
                try: server.wait(timeout=5)
                except subprocess.TimeoutExpired: server.kill(); server.wait()
                print(log_path.read_text())

if __name__ == "__main__":
    os.umask(0o077)
    parser = argparse.ArgumentParser()
    parser.add_argument("--cable", action="store_true")
    args = parser.parse_args()
    run("cable_probe.gd" if args.cable else "network_probe.gd")
