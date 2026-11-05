#!/usr/bin/env python3
"""Exercise archive validation and actual install/rollback in disposable folders."""
from pathlib import Path
import hashlib
import struct
import subprocess
import tempfile
import zipfile
ROOT=Path(__file__).resolve().parents[1]
ENGINE=ROOT/'.tools/Godot_v4.6.3-stable_linux.x86_64'
def archive(path,contents):
    with zipfile.ZipFile(path,'w',zipfile.ZIP_DEFLATED) as z:
        for name,data in contents.items():z.writestr(name,data)
def run():
    with tempfile.TemporaryDirectory(dir=ROOT/'.local') as temp:
        folder=Path(temp)
        archive(folder/'valid.zip',{'DQMOnline/DQMOnline.x86_64':b'new binary','DQMOnline/DQMOnline.pck':b'new resources','DQMOnline/libtest.so':b'new native library'})
        archive(folder/'traversal.zip',{'DQMOnline/../escape':b'unsafe'})
        archive(folder/'rom.zip',{'DQMOnline/cobi.gbc':b'not allowed'})
        bad=bytearray((folder/'valid.zip').read_bytes());i=bad.index(b'PK\x01\x02');struct.pack_into('<I',bad,i+24,314572801);(folder/'huge.zip').write_bytes(bad)
        p=subprocess.run([str(ENGINE),'--headless','--path',str(ROOT/'client'),'--script',str(ROOT/'tests/updater_probe.gd'),'--',f'--fixtures={folder}',f'--save-root={folder}/profile','--skip-onboarding=true'],capture_output=True,text=True,timeout=20)
        print(p.stdout,p.stderr);assert p.returncode==0 and 'PASS:' in p.stdout
        def install(name,fail=False):
            target=folder/name;target.mkdir();(target/'DQMOnline.x86_64').write_bytes(b'old binary');(target/'DQMOnline.pck').write_bytes(b'old resources')
            if fail:(target/'libtest.so').mkdir()
            package=folder/'valid.zip'
            p=subprocess.run([str(ENGINE),'--headless','--path',str(ROOT/'client'),'--','--update-worker=true',f'--install={target}',f'--archive={package}',f'--sha256={hashlib.sha256(package.read_bytes()).hexdigest()}','--parent=0','--restart=false'],capture_output=True,text=True,timeout=20)
            print(p.stdout,p.stderr)
            if fail:
                assert p.returncode==1 and 'UPDATE_FAILED' in p.stdout
                assert (target/'DQMOnline.x86_64').read_bytes()==b'old binary' and (target/'DQMOnline.pck').read_bytes()==b'old resources'
            else:
                assert p.returncode==0 and 'UPDATE_APPLIED' in p.stdout
                assert (target/'DQMOnline.x86_64').read_bytes()==b'new binary' and (target/'DQMOnline.pck').read_bytes()==b'new resources'
                assert (target/'DQMOnline.x86_64').stat().st_mode&0o111
        install('success');install('rollback',True)
        print('PASS: desktop updater replaces files and restores previous executable/resources after install failure')
if __name__=='__main__':run()
