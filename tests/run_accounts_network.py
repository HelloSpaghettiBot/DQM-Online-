#!/usr/bin/env python3
"""Register/login over HTTP, consume tickets on two real WebSocket clients."""
import importlib.util
import json
from pathlib import Path
import socket
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time
from urllib.request import Request, urlopen
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from run import godot, prepare
spec = importlib.util.spec_from_file_location("service", ROOT / "web/service.py")
service = importlib.util.module_from_spec(spec)
spec.loader.exec_module(service)

def run():
    prepare()
    engine = godot()
    with tempfile.TemporaryDirectory(dir=ROOT / ".local") as directory:
        directory = Path(directory)
        database = directory / "accounts.db"
        service.initialize(database)
        http = service.ThreadingHTTPServer(("127.0.0.1", 0), service.Handler)
        http.database = database
        http.public = ROOT / "web/public"
        http.status_file = directory / "status.json"
        http.origins = ["https://403world.com"]
        thread = threading.Thread(target=http.serve_forever, daemon=True)
        thread.start()
        with socket.socket() as reservation:
            reservation.bind(("127.0.0.1", 0))
            port = reservation.getsockname()[1]
        clients = []
        server = None
        try:
            tickets = {}
            for name in ("alice", "bob"):
                for action in ("register", "login"):
                    request = Request(f"http://127.0.0.1:{http.server_port}/DQM/api/{action}", json.dumps({"username": name, "password": "a unique test password 734902"}).encode(), {"Content-Type": "application/json", "Origin": "https://403world.com"})
                    with urlopen(request, timeout=10) as response:
                        result = json.load(response)
                        if action == "login": tickets[name] = result["ticket"]
            credentials = directory / "tickets.json"
            credentials.write_text(json.dumps(tickets))
            log_path = directory / "server.log"
            with log_path.open("w") as log:
                server = subprocess.Popen([engine, "--headless", "--path", str(ROOT / "server"), "--", f"--db={database}", f"--port={port}", "--transport=websocket", f"--status={http.status_file}"], stdout=log, stderr=log)
                deadline = time.monotonic() + 10
                while time.monotonic() < deadline:
                    if '"listening"' in log_path.read_text(): break
                    if server.poll() is not None: raise RuntimeError(log_path.read_text())
                    time.sleep(0.1)
                else: raise RuntimeError("Server did not start")
                for name in ("alice", "bob"):
                    clients.append(subprocess.Popen([engine, "--headless", "--path", str(ROOT / "client"), "--script", str(ROOT / "tests/network_probe.gd"), "--", f"--account={name}", f"--credentials={credentials}", f"--port={port}", "--transport=websocket"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True))
                for client in clients:
                    output = client.communicate(timeout=30)[0]
                    print(output)
                    assert client.returncode == 0, "WebSocket client failed"
                with sqlite3.connect(database) as db:
                    assert db.execute("SELECT count(*) FROM login_tickets").fetchone()[0] == 0, "Tickets were not consumed"
                    assert db.execute("SELECT count(*) FROM games").fetchone()[0] == 2, "Account isolation failed"
                print("PASS: account registration + password login + single-use tickets + two WebSocket clients + chat + relay + isolated server adventures")
        finally:
            for client in clients:
                if client.poll() is None: client.kill(); client.wait()
            if server:
                server.terminate()
                try: server.wait(timeout=5)
                except subprocess.TimeoutExpired: server.kill(); server.wait()
                print(log_path.read_text())
            http.shutdown(); http.server_close(); thread.join()

if __name__ == "__main__": run()
