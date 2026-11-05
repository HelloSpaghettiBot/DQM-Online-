#!/usr/bin/env python3
"""Capture two real clients using private ROM/state fixtures in an isolated server."""
import argparse
import os
from pathlib import Path
import socket
import sqlite3
import subprocess
import sys
import tempfile
import time
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from accounts import demo
from run import godot,prepare

def run(rom,state,other,output,mobile=False,movement=False):
    output.mkdir(parents=True,exist_ok=True);prepare();engine=godot();processes=[];logs=[]
    with tempfile.TemporaryDirectory(dir=ROOT/'.local') as temporary:
        folder=Path(temporary);database=folder/'shots.db';keys=folder/'keys.json';demo(database,keys)
        with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as reserved:reserved.bind(('127.0.0.1',0));port=reserved.getsockname()[1]
        try:
            stream=(folder/'server.log').open('w');logs.append(stream)
            server=subprocess.Popen([engine,'--headless','--path',str(ROOT/'server'),'--',f'--db={database}',f'--port={port}'],stdout=stream,stderr=stream);processes.append(server)
            deadline=time.monotonic()+10
            while '"listening"' not in (folder/'server.log').read_text() and time.monotonic()<deadline:
                assert server.poll() is None,(folder/'server.log').read_text();time.sleep(.05)
            with sqlite3.connect(database) as db:
                for name,fixture in [('alice',state),('bob',other)]:
                    account=db.execute('SELECT id FROM accounts WHERE username=?',(name,)).fetchone()[0]
                    db.execute('INSERT INTO games(account_id,slot,revision,sram_hex,state_hex) VALUES(?,1,1,?,?)',(account,bytes(32768).hex(),fixture.read_bytes().hex()))
            for name in ['alice','bob']:
                stream=(folder/(name+'.log')).open('w');logs.append(stream)
                args=[engine,'--path',str(ROOT/'client'),'--audio-driver','Dummy','--script',str(ROOT/'tests/visual_probe.gd'),'--',f'--rom={rom}',f'--save-root={folder}/profiles',f'--profile={name}',f'--dev-account={name}',f'--credentials={keys}','--host=127.0.0.1','--connect',f'--port={port}',f'--output={output}/{name}.png']
                if name=='alice' and mobile: args += ['--mobile-preview=true','--stretch=true']
                if name=='alice' and movement: args += ['--movement-check=true']
                if name=='alice':args += [f'--menu-output={output}/menu.png',f'--players-output={output}/players.png',f'--games-output={output}/adventures.png']
                else:args += ['--linger=3']
                processes.append(subprocess.Popen(args,stdout=stream,stderr=stream))
            for process in processes[1:]:process.wait(timeout=35)
            for name in ['alice','bob']:print((folder/(name+'.log')).read_text()[-900:])
            assert all(process.returncode==0 for process in processes[1:])
            with sqlite3.connect(database) as db:
                looks = db.execute('SELECT username,sprite,palette FROM appearances JOIN accounts ON account_id=accounts.id ORDER BY username').fetchall()
                assert looks == [('alice',23,1),('bob',80,5)],looks
            assert all('SCRIPT ERROR' not in (folder/(name+'.log')).read_text() for name in ['alice','bob'])
        finally:
            for process in processes:
                if process.poll() is None:process.terminate();process.wait(timeout=5)
            for stream in logs:stream.close()
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--rom',type=Path,required=True);p.add_argument('--state',type=Path,required=True);p.add_argument('--other-state',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--mobile',action='store_true');p.add_argument('--movement',action='store_true');a=p.parse_args();run(a.rom.resolve(),a.state.resolve(),a.other_state.resolve(),a.output.resolve(),a.mobile,a.movement)
