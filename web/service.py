#!/usr/bin/env python3
"""DQM account API and public pages. Bind only behind the HTTPS reverse proxy."""
from collections import defaultdict, deque
import argparse
import hashlib
import hmac
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import logging
import mimetypes
import os
from pathlib import Path
import re
import secrets
import sqlite3
import threading
import time
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parent
PREFIX = "/DQM"
HASH_N = 2**17
HASH_R = 8
HASH_P = 1
HASH_MEMORY = 256 * 1024 * 1024
HASH_SLOTS = threading.BoundedSemaphore(2)
DUMMY_SALT = bytes.fromhex("5d912b43f653404c9a3e21b970156adc")

def password_hash(password, salt):
    return hashlib.scrypt(password.encode("utf-8"), salt=salt, n=HASH_N, r=HASH_R,
                          p=HASH_P, maxmem=HASH_MEMORY, dklen=32).hex()

def initialize(database):
    database.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(database) as db:
        db.execute("PRAGMA journal_mode=WAL")
        db.execute("PRAGMA foreign_keys=ON")
        db.execute("CREATE TABLE IF NOT EXISTS accounts (id INTEGER PRIMARY KEY, username TEXT UNIQUE NOT NULL, key_hash TEXT NOT NULL)")
        columns = {r[1] for r in db.execute("PRAGMA table_info(accounts)")}
        for name in ("password_hash", "password_salt"):
            if name not in columns: db.execute(f"ALTER TABLE accounts ADD COLUMN {name} TEXT")
        db.execute("CREATE TABLE IF NOT EXISTS login_tickets (token_hash TEXT PRIMARY KEY, account_id INTEGER NOT NULL REFERENCES accounts(id), expires_at INTEGER NOT NULL)")
    os.chmod(database, 0o600)

class RateLimit:
    def __init__(self):
        self.lock = threading.Lock()
        self.requests = defaultdict(deque)

    def allow(self, key, limit, window):
        now = time.monotonic()
        with self.lock:
            if len(self.requests) > 10000:
                for old in list(self.requests):
                    if not self.requests[old] or self.requests[old][-1] < now - 3600:
                        del self.requests[old]
            bucket = self.requests[key]
            while bucket and bucket[0] <= now - window: bucket.popleft()
            if len(bucket) >= limit: return False
            bucket.append(now)
            return True

RATE = RateLimit()

class Handler(BaseHTTPRequestHandler):
    server_version = "DQM"

    def log_message(self, fmt, *args):
        logging.info("HTTP %s %s", self.command, getattr(self, "response_status", "-"))

    def send_response(self, code, message=None):
        self.response_status = code
        super().send_response(code, message)

    def headers_common(self):
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "same-origin")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Content-Security-Policy", "default-src 'self'; style-src 'self'; script-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'")

    def json(self, status, payload):
        data = json.dumps(payload, separators=(",", ":")).encode()
        self.send_response(status)
        self.headers_common()
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        path = unquote(urlsplit(self.path).path)
        if path == PREFIX:
            self.send_response(308)
            self.send_header("Location", PREFIX + "/")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if path == PREFIX + "/api/status":
            status = {"online": False, "players": 0, "version": "0.2.0-alpha", "max_players": 32}
            try:
                recent = self.server.status_file.stat().st_mtime > time.time() - 10
                if recent:
                    raw = json.loads(self.server.status_file.read_text())
                    status.update({"online": True, "players": int(raw["players"]), "uptime_seconds": int(raw["uptime_seconds"])})
            except (OSError, ValueError, KeyError, TypeError): pass
            manifest = self.server.public / "downloads/manifest.json"
            try: status["downloads"] = json.loads(manifest.read_text())
            except (OSError, ValueError): status["downloads"] = []
            self.json(200, status)
            return
        routes = {
            PREFIX + "/": "index.html",
            PREFIX + "/source/": "source/index.html",
            PREFIX + "/server/": "server/index.html",
        }
        if path in (PREFIX + "/source", PREFIX + "/server"):
            self.send_response(308)
            self.send_header("Location", path + "/")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        relative = routes.get(path)
        if relative is None:
            if not path.startswith(PREFIX + "/"):
                self.json(404, {"error": "Page not found."}); return
            relative = path[len(PREFIX) + 1:]
        target = (self.server.public / relative).resolve()
        if not target.is_relative_to(self.server.public.resolve()) or not target.is_file():
            self.json(404, {"error": "Page not found."}); return
        content_type = mimetypes.guess_type(target)[0] or "application/octet-stream"
        self.send_response(200)
        self.headers_common()
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(target.stat().st_size))
        self.send_header("Cache-Control", "no-cache")
        if target.suffix in (".zip", ".apk", ".tar.gz"):
            self.send_header("Content-Disposition", f'attachment; filename="{target.name}"')
        self.end_headers()
        with target.open("rb") as source:
            while chunk := source.read(1024 * 1024): self.wfile.write(chunk)

    def do_POST(self):
        path = urlsplit(self.path).path
        if path not in (PREFIX + "/api/register", PREFIX + "/api/login"):
            self.json(404, {"error": "Unknown endpoint."}); return
        origin = self.headers.get("Origin")
        if origin and origin not in self.server.origins:
            self.json(403, {"error": "Request origin is not allowed."}); return
        if self.headers.get("Content-Type", "").split(";")[0] != "application/json":
            self.json(415, {"error": "Send a JSON request."}); return
        try: length = int(self.headers.get("Content-Length", "0"))
        except ValueError: length = 0
        if not 1 <= length <= 4096:
            self.close_connection = True
            self.json(413, {"error": "Request is too large."}); return
        ip = self.headers.get("X-Real-IP", self.client_address[0])
        if not RATE.allow((ip, path), 5 if path.endswith("register") else 12, 300):
            self.json(429, {"error": "Too many attempts. Please wait a few minutes."}); return
        try:
            payload = json.loads(self.rfile.read(length))
            username = payload["username"].strip().lower()
            password = payload["password"]
            if not isinstance(username, str) or not isinstance(password, str): raise ValueError()
        except (ValueError, KeyError, TypeError, AttributeError):
            self.json(400, {"error": "Enter an account name and password."}); return
        if not re.fullmatch(r"[a-z0-9_]{3,24}", username):
            self.json(400, {"error": "Account names use 3–24 letters, numbers or underscores."}); return
        if not 12 <= len(password) <= 128:
            self.json(400, {"error": "Use a password between 12 and 128 characters."}); return
        if not HASH_SLOTS.acquire(blocking=False):
            self.json(503, {"error": "Sign-in is busy. Please try again in a moment."}); return
        try:
            if path.endswith("register"): self.register(username, password)
            else: self.login(username, password)
        finally:
            HASH_SLOTS.release()

    def register(self, username, password):
        salt = secrets.token_bytes(16)
        digest = password_hash(password, salt)
        try:
            with sqlite3.connect(self.server.database, timeout=10) as db:
                db.execute("INSERT INTO accounts(username,key_hash,password_hash,password_salt) VALUES(?,?,?,?)",
                           (username, secrets.token_hex(32), digest, salt.hex()))
            self.json(201, {"username": username, "message": "Account created. Use this account and password in the game client."})
        except sqlite3.IntegrityError:
            self.json(409, {"error": "That account name is already in use."})

    def login(self, username, password):
        with sqlite3.connect(self.server.database, timeout=10) as db:
            row = db.execute("SELECT id,password_hash,password_salt FROM accounts WHERE username=?", (username,)).fetchone()
        salt = bytes.fromhex(row[2]) if row and row[2] else DUMMY_SALT
        expected = row[1] if row and row[1] else "0" * 64
        digest = password_hash(password, salt)
        if not hmac.compare_digest(digest, expected):
            self.json(401, {"error": "Account name or password is incorrect."}); return
        ticket = secrets.token_hex(32)
        now = int(time.time())
        with sqlite3.connect(self.server.database, timeout=10) as db:
            db.execute("DELETE FROM login_tickets WHERE expires_at < ?", (now,))
            db.execute("INSERT INTO login_tickets(token_hash,account_id,expires_at) VALUES(?,?,?)",
                       (hashlib.sha256(ticket.encode()).hexdigest(), row[0], now + 60))
        self.json(200, {"username": username, "ticket": ticket, "expires_in": 60})

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", type=Path, required=True)
    parser.add_argument("--public", type=Path, default=ROOT / "public")
    parser.add_argument("--status", type=Path, required=True)
    parser.add_argument("--port", type=int, default=9045)
    parser.add_argument("--origin", action="append", default=["https://403world.com"])
    args = parser.parse_args()
    os.umask(0o077)
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
    initialize(args.database)
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    server.database = args.database
    server.public = args.public
    server.status_file = args.status
    server.origins = args.origin
    server.serve_forever()

if __name__ == "__main__": main()
