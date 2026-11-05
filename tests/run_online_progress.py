#!/usr/bin/env python3
"""Actual ROM progress: account saves, restart, fresh device, UDP blackhole lease."""
import argparse
import json
from pathlib import Path
import socket
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from run import prepare, godot
from accounts import demo

def run(rom, state, other_state):
    prepare(); engine = godot()
    with tempfile.TemporaryDirectory(prefix='online-progress-', dir=ROOT/'.local') as temporary:
        folder=Path(temporary);database=folder/'test.db';credentials=folder/'keys.json';demo(database,credentials)
        expected=folder/'expected.json';log=folder/'server.log';server=None;clients=[]
        with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as reserved:
            reserved.bind(('127.0.0.1',0));port=reserved.getsockname()[1]
        def start_server():
            stream=log.open('w')
            process=subprocess.Popen([engine,'--headless','--path',str(ROOT/'server'),'--',f'--db={database}',f'--port={port}'],stdout=stream,stderr=stream);stream.close()
            deadline=time.monotonic()+10
            while time.monotonic()<deadline:
                if '"listening"' in log.read_text():return process
                if process.poll() is not None:raise RuntimeError(log.read_text())
                time.sleep(.05)
            raise RuntimeError('Server startup timeout: '+log.read_text())
        def client(mode, client_port=port):
            profile=folder/mode/'default';profile.mkdir(parents=True)
            # Deliberately conflicting old local progress must be ignored.
            (profile/'cobi.state').write_bytes(other_state.read_bytes());(profile/'cobi.srm').write_bytes(bytes([99])*32768)
            output=folder/(mode+'.log');stream=output.open('w')
            process=subprocess.Popen([engine,'--headless','--path',str(ROOT/'client'),'--script',str(ROOT/'tests/online_progress_probe.gd'),'--',f'--rom={rom}',f'--save-root={profile.parent}','--dev-account=alice',f'--credentials={credentials}','--host=127.0.0.1',f'--port={client_port}','--skip-onboarding=true',f'--mode={mode}',f'--expected={expected}'],stdout=stream,stderr=stream);stream.close();clients.append(process)
            return process,output,profile
        def finish(process, output, profile):
            process.wait(timeout=25);print(output.read_text());assert process.returncode==0
            assert 'PASS:' in output.read_text() and 'SCRIPT ERROR' not in output.read_text()
            assert (profile/'cobi.state').read_bytes()==other_state.read_bytes(),'Client wrote a local checkpoint'
            assert (profile/'cobi.srm').read_bytes()==bytes([99])*32768,'Client wrote local SRAM'
        try:
            server=start_server()
            with sqlite3.connect(database) as db:
                account=db.execute("SELECT id FROM accounts WHERE username='alice'").fetchone()[0]
                db.execute('INSERT INTO games(account_id,slot,revision,sram_hex,state_hex) VALUES(?,1,1,?,?)',(account,bytes(32768).hex(),state.read_bytes().hex()))
            p,out,profile=client('write');finish(p,out,profile)
            server.terminate();server.wait(timeout=5);server=start_server()
            p,out,profile=client('read');finish(p,out,profile)
            # Drop packets without closing TCP/ENet; only the client heartbeat gate can notice promptly.
            proxy=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);proxy.bind(('127.0.0.1',0));proxy.settimeout(.1)
            proxy_port=proxy.getsockname()[1];stop=threading.Event();drop=threading.Event();address=[None]
            def relay():
                while not stop.is_set():
                    try:data,origin=proxy.recvfrom(65535)
                    except socket.timeout:continue
                    if drop.is_set():continue
                    if origin==('127.0.0.1',port):
                        if address[0]:proxy.sendto(data,address[0])
                    else:address[0]=origin;proxy.sendto(data,('127.0.0.1',port))
            thread=threading.Thread(target=relay,daemon=True);thread.start()
            p,out,profile=client('disconnect',proxy_port)
            deadline=time.monotonic()+15
            while time.monotonic()<deadline and 'READY_TO_DISCONNECT' not in out.read_text():
                assert p.poll() is None,out.read_text();time.sleep(.05)
            assert 'READY_TO_DISCONNECT' in out.read_text(),out.read_text()
            drop.set();finish(p,out,profile);stop.set();thread.join(timeout=2);proxy.close()
            with sqlite3.connect(database) as db:
                assert db.execute('SELECT count(*) FROM games WHERE account_id=?',(account,)).fetchone()[0]==2
            print('PASS: online-only gameplay, account/device/restart persistence, slots, local save isolation, connection-loss lease')
        finally:
            for process in clients:
                if process.poll() is None:process.kill();process.wait()
            if server and server.poll() is None:server.terminate();server.wait(timeout=5)
            print(log.read_text())
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--rom',type=Path,required=True);parser.add_argument('--state',type=Path,required=True);parser.add_argument('--other-state',type=Path,required=True);args=parser.parse_args();run(args.rom.resolve(),args.state.resolve(),args.other_state.resolve())
