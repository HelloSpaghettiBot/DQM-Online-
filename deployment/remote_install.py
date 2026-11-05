#!/usr/bin/env python3
"""Install one pre-uploaded DQM release, preserving unrelated VPS services."""
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import pwd
import shutil
import sqlite3
import subprocess
import sys
import time
from urllib.request import urlopen

def command(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)

def main():
    assert os.geteuid() == 0, "Run the installer as root"
    assert os.uname().nodename == "racknerd-2872c8f", "Unexpected VPS"
    stage = Path(sys.argv[1]).resolve()
    assert stage.parent == Path('/opt/dqmonline/releases')
    required = ['web/service.py', 'web/public/index.html', 'server/main.tscn',
                'web/public/downloads/DQMOnline-source.zip',
                'web/public/downloads/DQMOnline-windows.zip',
                'web/public/downloads/DQMOnline-linux.zip',
                'web/public/downloads/DQMOnline-android.apk']
    for name in required: assert (stage / name).is_file(), f"Missing {name}"
    expected_version = json.loads((stage / 'web/public/downloads/manifest.json').read_text())[0]['version']
    config = Path('/etc/nginx/sites-enabled/403world.com').resolve()
    before = config.read_bytes()
    marker = b'root /var/www/403world.com; index index.html;'
    assert before.count(marker) == 1, 'Review changed nginx configuration before install'
    base = Path('/opt/dqmonline')
    current = base / 'current'
    previous = os.readlink(current) if current.is_symlink() else None
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    backup = Path('/var/backups/dqmonline-deploy') / stamp
    backup.mkdir(parents=True, mode=0o700)
    shutil.copy2(config, backup / 'nginx-before.conf')
    snippet = Path('/etc/nginx/snippets/dqmonline.conf')
    installed = [Path('/etc/systemd/system') / source.name for source in (stage / 'deployment/systemd').glob('*')]
    for path in [snippet, *installed]:
        if path.exists(): shutil.copy2(path, backup / (path.name + '.before'))
    (backup / 'rollback.json').write_text(json.dumps({'previous_release': previous, 'new_release': str(stage), 'config': str(config)}))
    data = Path('/var/lib/dqmonline')
    data.mkdir(mode=0o700, exist_ok=True)
    try: account = pwd.getpwnam('dqmonline')
    except KeyError:
        command('useradd', '--system', '--home-dir', str(data), '--shell', '/usr/sbin/nologin', 'dqmonline')
        account = pwd.getpwnam('dqmonline')
    database = data / 'dqmonline.db'
    if database.exists():
        with sqlite3.connect(database) as source, sqlite3.connect(backup / 'database-before.db') as dest:
            source.backup(dest)
    spec = importlib.util.spec_from_file_location('dqm_service', stage / 'web/service.py')
    service = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(service)
    service.initialize(database)
    for path in [data, *data.iterdir()]: os.chown(path, account.pw_uid, account.pw_gid)
    os.chmod(data, 0o700)
    os.chmod(database, 0o600)
    engine = '/opt/dqmonline/runtime/Godot_v4.6.3-stable_linux.x86_64'
    import_log = backup / 'server-import.log'
    for attempt in range(3):
        with import_log.open('a') as log:
            result = subprocess.run([engine, '--headless', '--verbose', '--editor', '--path', str(stage / 'server'), '--import'], stdout=log, stderr=log, timeout=90)
        if result.returncode == 0: break
        if result.returncode != -6 or attempt == 2:
            raise RuntimeError('Server import failed before release activation. See ' + str(import_log))

    for directory in stage.rglob('*'):
        if directory.is_dir(): directory.chmod(0o755)
        elif directory.is_file(): directory.chmod(0o644)
    stage.chmod(0o755)
    link = base / '.next'
    link.unlink(missing_ok=True)
    link.symlink_to(stage)
    try:
        # Check the file once more before its narrow route edit.
        assert config.read_bytes() == before, 'nginx changed during preparation'
        os.replace(link, current)
        for source in (stage / 'deployment/systemd').glob('*'):
            shutil.copy2(source, Path('/etc/systemd/system') / source.name)
        shutil.copy2(stage / 'deployment/nginx-dqm.conf', snippet)
        include = b'include /etc/nginx/snippets/dqmonline.conf;'
        if include not in before:
            config.write_bytes(before.replace(marker, include + b'\n' + marker, 1))
        command('systemctl', 'daemon-reload')
        command('systemctl', 'enable', 'dqmonline-web', 'dqmonline-game', 'dqmonline-backup.timer')
        command('systemctl', 'restart', 'dqmonline-web')
        command('systemctl', 'restart', 'dqmonline-game')
        command('systemctl', 'start', 'dqmonline-backup.timer')
        for attempt in range(50):
            try:
                with urlopen('http://127.0.0.1:9045/DQM/api/status', timeout=2) as response:
                    status = json.load(response)
                if status['online'] and json.loads((data / 'status.json').read_text()).get('version') == expected_version:
                    command('systemctl', 'is-active', '--quiet', 'dqmonline-web', 'dqmonline-game')
                    break
            except Exception: pass
            time.sleep(0.2)
        else: raise RuntimeError('DQM service health check failed')
        command('nginx', '-t')
        command('systemctl', 'reload', 'nginx')
        print(json.dumps({'installed': True, 'url': 'https://403world.com/DQM/', 'source': 'https://403world.com/DQM/source/', 'release': str(stage), 'backup': str(backup), 'status': status['online']}))
    except Exception:
        shutil.copy2(backup / 'nginx-before.conf', config)
        if previous:
            current.unlink(missing_ok=True)
            current.symlink_to(previous)
        else:
            current.unlink(missing_ok=True)
            subprocess.run(['systemctl', 'disable', '--now', 'dqmonline-game', 'dqmonline-web', 'dqmonline-backup.timer'])
        for path in [snippet, *installed]:
            saved = backup / (path.name + '.before')
            if saved.exists(): shutil.copy2(saved, path)
            else: path.unlink(missing_ok=True)
        subprocess.run(['systemctl', 'daemon-reload'])
        if previous: subprocess.run(['systemctl', 'restart', 'dqmonline-web', 'dqmonline-game'])
        subprocess.run(['nginx', '-t'], check=True)
        subprocess.run(['systemctl', 'reload', 'nginx'], check=True)
        raise

if __name__ == '__main__': main()
