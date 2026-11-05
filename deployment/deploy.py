#!/usr/bin/env python3
"""Upload an explicit release to the owner's configured VPS; no secrets packaged."""
import argparse
import hashlib
import json
from pathlib import Path
import shlex
import subprocess
import tarfile
ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ssh-helper', type=Path)
    parser.add_argument('--host', default='root@192.236.168.86')
    parser.add_argument('--release', default='0.1.0-alpha-20261104-01')
    args = parser.parse_args()
    if not args.release.replace('-', '').replace('.', '').isalnum(): parser.error('Invalid release label')
    archive = ROOT / '.local/site-release.tar.gz'
    forbidden = {'.git', '.godot', '.local', '.tools', '__pycache__', 'private'}
    with tarfile.open(archive, 'w:gz') as output:
        for folder in ['server', 'shared', 'web', 'deployment']:
            for source in sorted((ROOT / folder).rglob('*')):
                if not source.is_file() or source.is_symlink(): continue
                relative = source.relative_to(ROOT)
                if set(relative.parts) & forbidden: continue
                if source.suffix.lower() in ['.db','.gb','.gbc','.gba','.sav','.srm','.state','.key','.pem','.jks','.keystore','.pyc','.log']:
                    raise ValueError(f'Forbidden release file: {relative}')
                if folder == 'server' and 'bin' in relative.parts and not source.name.endswith(('linux.template_debug.x86_64.so', 'linux.template_release.x86_64.so')): continue
                output.add(source, arcname=str(relative))
    checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
    release = '/opt/dqmonline/releases/' + args.release
    remote = '''from pathlib import Path
import sys,hashlib,tarfile,os,subprocess
assert os.uname().nodename=='racknerd-2872c8f'
archive=Path('/var/tmp/dqmonline-release-upload.tar.gz')
with archive.open('wb') as f:
 while block:=sys.stdin.buffer.read(1048576):f.write(block)
assert hashlib.sha256(archive.read_bytes()).hexdigest()==CHECKSUM
stage=Path(RELEASE)
assert not stage.exists(),'Release exists; choose a new release label'
stage.mkdir(parents=True)
with tarfile.open(archive) as source:
 assert all(member.isfile() and not member.name.startswith('/') and '..' not in Path(member.name).parts for member in source.getmembers())
 source.extractall(stage,filter='data')
subprocess.run(['python3',str(stage/'deployment/remote_install.py'),str(stage)],check=True)
'''.replace('CHECKSUM', repr(checksum)).replace('RELEASE', repr(release))
    command = 'python3 -c ' + shlex.quote(remote)
    ssh = ['python3', str(args.ssh_helper)] if args.ssh_helper else ['ssh']
    print(f'Uploading {archive.stat().st_size} bytes to {args.host}; expected checksum {checksum}', flush=True)
    with archive.open('rb') as incoming:
        result = subprocess.run([*ssh, args.host, command], stdin=incoming, capture_output=True, timeout=300)
    print(result.stdout.decode())
    print(result.stderr.decode())
    result.check_returncode()

if __name__ == '__main__': main()
