'use strict';
const fs=require('node:fs');const {createRequire}=require('node:module');const {spawnSync}=require('node:child_process');const crypto=require('node:crypto');
const repo=process.argv[2]||'E:/temp/alula-pr3-20261117';const prefix=process.argv[3]||'E:/Temp/alula-p0582-watchdog-validation';
const requireLocal=createRequire('C:/Users/Vegetable/AppData/Roaming/npm/node_modules/gitnexus/package.json');
const file=repo+'/.github/workflows/platform-availability.yml';const swift=repo+'/tools/vscode-parity/macos-native-dnd-input.swift';
const content=fs.readFileSync(file,'utf8');const workflow=requireLocal('js-yaml').load(content);const body=workflow.jobs.macos.steps.find(x=>x.name==='Launch macOS native-titlebar mode and verify native Quit menu').run;
const watchdog=body.split("<<'PY'\n")[1].split('\nPY\n')[0];
const functionBody=body.slice(body.indexOf('native_watchdog() {'),body.indexOf('rm -f "$target"'));
const cleanup=body.slice(body.indexOf('cleanup() {'),body.indexOf('trap cleanup EXIT'));
const results={repo,workflowSHA256:crypto.createHash('sha256').update(content).digest('hex'),swiftSHA256:crypto.createHash('sha256').update(fs.readFileSync(swift)).digest('hex'),limits:'POSIX tests run on WSL Linux, not macOS; Swift untouched and not executed',checks:[]};
for(const[job,data]of Object.entries(workflow.jobs))for(const s of data.steps){if(typeof s.run!=='string'||['powershell','pwsh'].includes(s.shell)||(job==='windows'&&!s.shell))continue;const x=spawnSync('C:/Program Files/Git/bin/bash.exe',['-n'],{input:s.run,encoding:'utf8'});results.checks.push({name:'bash-syntax '+s.name,passed:x.status===0,stderr:x.stderr});}
const harness=`import json, os, pathlib, signal, subprocess, sys, tempfile, time
watchdog = ${JSON.stringify(watchdog)}
function_body = ${JSON.stringify(functionBody)}
cleanup_body = ${JSON.stringify(cleanup)}
results=[]
def record(name, action):
    start=time.monotonic()
    try:
        details=action()
        results.append(dict(name=name,passed=True,elapsed=time.monotonic()-start,details=details))
    except Exception as e:
        results.append(dict(name=name,passed=False,elapsed=time.monotonic()-start,error=repr(e)))
with tempfile.TemporaryDirectory(prefix='alula-watchdog-') as directory:
    root=pathlib.Path(directory)
    script=root/'watchdog.py'; script.write_text(watchdog)
    log=root/'child.log'
    def run(seconds,stage,command,capture='log',deadline=None):
        return subprocess.run([sys.executable,'-I','-u',str(script),str(log),'run',str(deadline or time.monotonic()+seconds),stage,capture,*command],capture_output=True,text=True,timeout=4)
    def status():
        p=run(2,'status',[sys.executable,'-I','-c','import sys; sys.exit(7)'])
        assert p.returncode==7,p
        return p.stderr
    record('preserve-command-status-7',status)
    def hanging():
        p=run(1.2,'hanging-parent',[sys.executable,'-I','-c','import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); time.sleep(30)'])
        assert p.returncode==124,p
        assert 'event=start' in p.stderr and 'event=timeout' in p.stderr,p.stderr
        return p.stderr
    record('hanging-parent-killed-within-budget',hanging)
    def descendants():
        pidfile=root/'descendant.pid'
        child='import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); time.sleep(30)'
        parent='import subprocess,sys,pathlib,signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); p=subprocess.Popen([sys.executable,"-I","-c",'+repr(child)+']); pathlib.Path(sys.argv[1]).write_text(str(p.pid)); time.sleep(30)'
        unrelated=subprocess.Popen([sys.executable,'-I','-c','import time; time.sleep(30)'])
        try:
            p=run(1.3,'descendants',[sys.executable,'-I','-c',parent,str(pidfile)],capture='pid')
            assert p.returncode==124,p
            pid=int(pidfile.read_text())
            state=pathlib.Path('/proc/'+str(pid)+'/stat')
            assert not state.exists() or state.read_text().split()[2]=='Z','descendant still running'
            assert unrelated.poll() is None,'unrelated process killed'
            return dict(stderr=p.stderr,descendantPID=pid,unrelatedSurvived=True)
        finally:
            unrelated.kill(); unrelated.wait(timeout=1)
    record('hanging-descendant-group-killed-and-unrelated-survives',descendants)
    def shared():
        deadline=time.monotonic()+1.6
        a=run(1,'attempt1',[sys.executable,'-I','-c','import time,sys; time.sleep(.4); sys.exit(1)'],deadline=deadline)
        delay=run(1,'retry-delay',['/bin/sleep','.2'],deadline=deadline)
        b=run(1,'attempt2',[sys.executable,'-I','-c','import time; time.sleep(30)'],deadline=deadline)
        assert (a.returncode,delay.returncode,b.returncode)==(1,0,124),(a,delay,b)
        assert time.monotonic()<deadline+.4,'shared budget reset'
        return [a.stderr,delay.stderr,b.stderr]
    record('shared-quit-budget-includes-retry-delay',shared)
    def observer():
        p=run(1.2,'observer',[sys.executable,'-I','-c','import time; time.sleep(30)'])
        assert p.returncode==124,p
        return 'external timeout fails; helper internal20s unchanged'
    record('observer-external-timeout-fails',observer)
    def cleanup_test():
        helper=root/'helper.py'
        helper.write_text('#!/usr/bin/env python3\\nimport time\\ntime.sleep(30)\\n')
        helper.chmod(0o755)
        target=root/'target.json'; target.write_text('{}')
        wrapper=subprocess.Popen([sys.executable,'-I','-c','import time; time.sleep(30)'])
        try:
            shell='set -e\\nlog='+repr(str(log))+'\\n'+function_body+'\\nhelper='+repr(str(helper))+'\\ntarget='+repr(str(target))+'\\napp_pid=424242\\nopen_pid='+str(wrapper.pid)+'\\n'+cleanup_body.replace('deadline 5','deadline 1.2')+'\\ntrap cleanup EXIT\\nexit 7\\n'
            p=subprocess.run(['/bin/bash','-s'],input=shell,capture_output=True,text=True,timeout=4)
            assert p.returncode==7,p
            wrapper.wait(timeout=1)
            assert 'pre-cleanup result=7' in p.stderr,p.stderr
            assert 'stage=cleanup-windows event=timeout' in p.stderr,p.stderr
            assert 'stage=cleanup-identity event=timeout' in p.stderr,p.stderr
            return dict(stderr=p.stderr,stdout=p.stdout,wrapperStatus=wrapper.returncode)
        finally:
            if wrapper.poll() is None: wrapper.kill(); wrapper.wait(timeout=1)
    record('actual-cleanup-hang-preserves7-and-still-stops-wrapper',cleanup_test)
    def bad_deadline():
        p=run(1,'bad',['/bin/true'],deadline=float('nan'))
        assert p.returncode!=0,p
        return p.stderr
    record('reject-nonfinite-deadline',bad_deadline)
print(json.dumps(results))
sys.exit(0 if all(r['passed'] for r in results) else 1)
`;
const native=spawnSync('wsl.exe',['--exec','python3','-I','-'],{input:harness,encoding:'utf8',timeout:45000,maxBuffer:8*1024*1024});
try{results.fixtures=JSON.parse(native.stdout.trim());}catch{results.fixtures=[];results.parseError=native.stdout;}
results.execution={status:native.status,stderr:native.stderr,error:native.error?String(native.error):null};
const whitespace=spawnSync('git',['-C',repo,'diff','--check','--','.github/workflows/platform-availability.yml'],{encoding:'utf8'});results.checks.push({name:'scoped-diff-check',passed:whitespace.status===0,stdout:whitespace.stdout,stderr:whitespace.stderr});
results.passed=native.status===0&&results.fixtures.length===7&&results.checks.every(x=>x.passed);
fs.writeFileSync(prefix+'.json',JSON.stringify(results,null,2)+'\n');fs.writeFileSync(prefix+'.log',results.checks.map(x=>(x.passed?'PASS ':'FAIL ')+x.name).join('\n')+'\n'+JSON.stringify(results.fixtures,null,2)+'\n'+JSON.stringify(results.execution)+'\n');
console.log(JSON.stringify({passed:results.passed,bashBlocks:results.checks.length-1,fixtures:results.fixtures.map(x=>({name:x.name,passed:x.passed,elapsed:x.elapsed,error:x.error})),json:prefix+'.json',log:prefix+'.log'},null,2));process.exitCode=results.passed?0:1;
