#!/usr/bin/env python3
"""Atomically update public pages/downloads without restarting game sessions."""
import argparse
import hashlib
from pathlib import Path
import shlex
import subprocess
import tarfile
ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ssh-helper', type=Path)
    parser.add_argument('--host', default='root@192.236.168.86')
    parser.add_argument('--release', required=True)
    args = parser.parse_args()
    if not args.release.replace('-', '').replace('.', '').isalnum(): parser.error('Invalid release label')
    archive = ROOT / '.local/public-release.tar.gz'
    with tarfile.open(archive, 'w:gz') as output:
        for source in sorted((ROOT / 'web/public').rglob('*')):
            if not source.is_file(): continue
            rel = source.relative_to(ROOT / 'web/public')
            if source.is_symlink() or source.suffix.lower() in {'.gb','.gbc','.gba','.db','.sav','.srm','.state','.log','.key','.pem','.keystore','.jks','.pyc'}:
                raise ValueError(f'Forbidden public file: {rel}')
            output.add(source, arcname=str(rel))
    checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
    remote = '''from pathlib import Path
import sys,hashlib,tarfile,os,shutil,json,time
assert os.uname().nodename=='racknerd-2872c8f'
base=Path('/opt/dqmonline')
upload=base/'public-upload.tar.gz'
with upload.open('wb') as f:
 while block:=sys.stdin.buffer.read(1048576):f.write(block)
assert hashlib.sha256(upload.read_bytes()).hexdigest()==CHECKSUM
previous=(base/'current').resolve()
release=base/'releases'/LABEL
assert previous.parent==base/'releases' and not release.exists()
# Clone immutable release files; never overwrite a hard-linked file in place.
shutil.copytree(previous,release,copy_function=os.link,symlinks=True)
public=release/'web/public'
shutil.rmtree(public)
public.mkdir(mode=0o755)
with tarfile.open(upload) as source:
 assert all(m.isfile() and not m.name.startswith('/') and '..' not in Path(m.name).parts for m in source.getmembers())
 source.extractall(public,filter='data')
for p in public.rglob('*'):p.chmod(0o755 if p.is_dir() else 0o644)
assert (public/'index.html').is_file() and (public/'downloads/DQMOnline-source.zip').is_file()
link=base/'current-next'
assert not link.exists() and not link.is_symlink()
link.symlink_to(release)
os.replace(link,base/'current')
(base/'public-update.json').write_text(json.dumps({'previous':str(previous),'current':str(release),'updated':int(time.time())})+'\\n')
upload.unlink()
print('Published '+str(release)+'; previous '+str(previous)+'; game processes unchanged')
'''.replace('CHECKSUM', repr(checksum)).replace('LABEL', repr(args.release))
    ssh = ['python3', str(args.ssh_helper)] if args.ssh_helper else ['ssh']
    print(f'Uploading public update: {archive.stat().st_size} bytes', flush=True)
    with archive.open('rb') as incoming:
        result = subprocess.run([*ssh, args.host, 'python3 -c ' + shlex.quote(remote)], stdin=incoming, capture_output=True, timeout=300)
    print(result.stdout.decode()); print(result.stderr.decode()); result.check_returncode()

if __name__ == '__main__': main()
