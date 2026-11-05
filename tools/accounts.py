#!/usr/bin/env python3
"""Offline account provisioning. Keys are 256 random bits, never passwords."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import sqlite3

ROOT = Path(__file__).resolve().parents[1]

def provision(database, username):
    if not re.fullmatch(r"[a-z0-9_]{1,24}", username):
        raise ValueError("Use 1–24 lowercase letters, digits or underscores.")
    database = Path(database)
    database.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(database)
    try:
        connection.execute("CREATE TABLE IF NOT EXISTS accounts (id INTEGER PRIMARY KEY, username TEXT UNIQUE NOT NULL, key_hash TEXT NOT NULL)")
        if connection.execute("SELECT 1 FROM accounts WHERE username=?", (username,)).fetchone():
            raise ValueError("Account already exists; existing keys are never overwritten.")
        key = secrets.token_hex(32)
        connection.execute("INSERT INTO accounts(username,key_hash) VALUES (?,?)", (username, hashlib.sha256(key.encode()).hexdigest()))
        connection.commit()
        os.chmod(database, 0o600)
        return key
    finally:
        connection.close()

def demo(database, credentials):
    credentials = Path(credentials)
    saved = json.loads(credentials.read_text()) if credentials.exists() else {}
    for name in ("alice", "bob"):
        if name not in saved:
            saved[name] = provision(database, name)
    credentials.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(credentials, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as output:
        json.dump(saved, output, indent=2)
    os.chmod(credentials, 0o600)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("username", nargs="?")
    parser.add_argument("--database", type=Path, default=ROOT / ".local/dqmonline.db")
    parser.add_argument("--demo", action="store_true")
    args = parser.parse_args()
    os.umask(0o077)
    if args.demo:
        demo(args.database, ROOT / ".local/dev_accounts.json")
        print("Created or retained local alice/bob development accounts.")
    elif args.username:
        print(provision(args.database, args.username))
    else:
        parser.error("Specify an account name or --demo.")
