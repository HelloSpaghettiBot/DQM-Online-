#!/usr/bin/env python3
"""Consistent SQLite backups, intended for the VPS root-owned daily timer."""
from datetime import datetime, timezone
from pathlib import Path
import os
import sqlite3

os.umask(0o077)
folder = Path('/var/backups/dqmonline')
folder.mkdir(mode=0o700, parents=True, exist_ok=True)
stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
target = folder / f'dqmonline-{stamp}.db'
with sqlite3.connect('/var/lib/dqmonline/dqmonline.db') as source, sqlite3.connect(target) as dest:
    source.backup(dest)
os.chmod(target, 0o600)
for old in sorted(folder.glob('dqmonline-*.db'))[:-14]:
    old.unlink()
