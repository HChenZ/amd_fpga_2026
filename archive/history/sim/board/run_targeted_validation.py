"""Preserve historical D-cache failures and validate the revised current tests.

Historical failures remain FAIL in the report; expected negative tests have a
separate gate verdict. Never edits production RTL or prior evidence.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

from common import ROOT, compiler_prefix, git, local_output, python_command, run, sha256, write_json


def read_vcd(path):
    names,scope,values,failures,requests,samples = {},[],{},[],[],[]
    now=0
    for line in path.read_text().splitlines():
        if line.startswith('$scope'):
            scope.append(line.split()[2])
        elif line.startswith('$upscope'):
            scope.pop()
        elif line.startswith('$var'):
            fields=line.split(); names['.'.join(scope+[fields[4]])]=fields[3]
        elif line.startswith('#'):
            now=int(line[1:])
        elif line and line[0] in '01xz':
            key,value=line[1:],line[0];values[key]=value
            if now and key==names.get('tb_dcache.bus_mem_re_o') and value=='1':
                requests.append(now)
        elif line.startswith('b'):
            value,key=line[1:].split(' ',1);values[key]=value
            if now and key==names.get('tb_dcache.errors'):
                failures.append((now,int(value,2)))
                sample={}
                for signal in ('bus_mem_re_o','bus_load_miss_o','bus_addr_o'):
                    raw=values[names['tb_dcache.'+signal]]
                    sample[signal]=int(raw,2)
                samples.append(sample)
    if failures!=[(36000,3),(206000,4)]:
        raise ValueError('legacy failure times/counts changed; re-diagnosis required')
    return dict(timescale='1ps',failure_events=failures,read_request_times_ps=requests,
                assertions=[dict(name='cold cacheable load bus load miss',time_ns=36,actual=samples[0]['bus_mem_re_o'],expected=1),
                    dict(name='cold cacheable load load miss pulse',time_ns=36,actual=samples[0]['bus_load_miss_o'],expected=1),
                    dict(name='cold cacheable load miss addr capture',time_ns=36,actual=f'0x{samples[0]["bus_addr_o"]:08x}',expected='0x10000000'),
                    dict(name='store miss target is still a load miss',time_ns=206,actual=samples[1]['bus_mem_re_o'],expected=1)])


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--mode',choices=('all','dcache','interrupt'),default='all')
    parser.add_argument('--cc-prefix',default='riscv64-unknown-elf-')
    a=parser.parse_args()
    out=local_output(a.out);out.mkdir(parents=True,exist_ok=False)
    start=time.monotonic()
    report=dict(schema_version=1,owner='TBD',task_id='V01/preboard_followup',source_head=git('rev-parse','HEAD'),
                git_status=git('status','--short'),timestamp_utc=datetime.now(timezone.utc).isoformat(),
                evidence_kind='rtl_simulation',commands=[],checks=[],classification='NOT_RUN')

    def execute(label,command,expected=0,marker=None,cwd=ROOT):
        row,text=run(command,cwd=cwd,timeout=120,log=out/(label+'.log'))
        row.update(name=label,expected_exit_code=expected)
        row['gate']='PASS' if row['exit_code']==expected and (not marker or marker in text) else 'FAIL'
        report['commands'].append(row)
        print(label,row['status'],'expected',expected,'gate',row['gate'],flush=True)
        return row,text

    def check(name,valid,**details):
        report['checks'].append(dict(name=name,status='PASS' if valid else 'FAIL',**details))

    def compile_tb(label,source,top,tb):
        exe=out/(label+'.vvp')
        row,_=execute(label+'_compile',['iverilog','-g2012','-I','src/rtl','-s',top,'-o',str(exe),str(source),tb])
        if row['gate']!='PASS': raise RuntimeError(label+' compilation failed')
        return exe

    try:
        execute('iverilog_version',['iverilog','-V'])
        execute('vvp_version',['vvp','-V'])
        if a.mode in ('all','dcache'):
            variants={}
            # Only individual historical RTL files are materialized, no repo/worktree copy.
            for label,revision in [('pre_miss_pipeline',git('rev-parse','3c6f134^')),
                                   ('pre_store_buffer',git('rev-parse','964d1a3^'))]:
                path=out/(label+'.v')
                path.write_bytes(subprocess.check_output(['git','show',revision+':src/rtl/dcache.v'],cwd=ROOT))
                variants[label]=path
                report.setdefault('control_sources',{})[label]=dict(revision=revision,path=str(path),sha256=sha256(path))
            variants['current']=ROOT/'src/rtl/dcache.v'
            # Freeze the published, uncorrected test for historical comparison.
            # Live tb_dcache.v must pass; its old FAIL is never re-labelled PASS.
            legacy_revision=git('rev-parse','68fafc8')
            legacy_tb=out/'tb_dcache_fixed_timing_snapshot.v'
            legacy_tb.write_bytes(subprocess.check_output(['git','show',legacy_revision+
                ':sim/original_cpu/unit/dcache/tb_dcache.v'],cwd=ROOT))
            report['historical_tb']=dict(revision=legacy_revision,path=str(legacy_tb),sha256=sha256(legacy_tb))
            historical_rtl=out/'dcache_published_snapshot.v'
            historical_rtl.write_bytes(subprocess.check_output(['git','show',legacy_revision+
                ':src/rtl/dcache.v'],cwd=ROOT))
            report['historical_tb']['rtl_sha256']=sha256(historical_rtl)
            historical_variants={k:v for k,v in variants.items() if k!='current'}
            historical_variants['published_snapshot']=historical_rtl
            for label,source in historical_variants.items():
                exe=compile_tb(label+'_legacy',source,'tb_dcache',legacy_tb)
                expected=0 if label=='pre_miss_pipeline' else 1
                execute(label+'_legacy',['vvp',str(exe)],expected=expected,
                        marker='tb_dcache PASS' if expected==0 else 'tb_dcache FAIL errors=4',cwd=out)
                if label=='published_snapshot':
                    report['legacy_failures']=read_vcd(out/'tb_dcache.vcd')
                shutil.copyfile(out/'tb_dcache.vcd',out/(label+'_legacy.vcd'))
            for label in ('pre_store_buffer','current'):
                revised=compile_tb(label+'_revised_tb',variants[label],'tb_dcache',
                                   'sim/original_cpu/unit/dcache/tb_dcache.v')
                execute(label+'_revised_tb',['vvp',str(revised)],marker='tb_dcache PASS',cwd=out)
                shutil.copyfile(out/'tb_dcache.vcd',out/(label+'_revised_tb.vcd'))
                exe=compile_tb(label+'_contract',variants[label],'tb_dcache_contract','sim/board/tb_dcache_contract.v')
                execute(label+'_contract',['vvp',str(exe)],marker='tb_dcache_contract PASS',cwd=out)
                trace=compile_tb(label+'_trace',variants[label],'tb_dcache_trace','build/timing_tests/tb_dcache_trace.v')
                for seed in (1,17,1234567,305419896):
                    path=out/(label+'_trace_'+str(seed)+'.txt')
                    execute(label+'_trace_'+str(seed),['vvp',str(trace),'+TRACE='+str(path),'+NOPS=1000','+SEED='+str(seed)],marker='TRACE DONE',cwd=out)
            for seed in (1,17,1234567,305419896):
                before=out/('pre_store_buffer_trace_'+str(seed)+'.txt')
                after=out/('current_trace_'+str(seed)+'.txt')
                check('store_buffer_cycle_diff_'+str(seed),before.read_bytes()==after.read_bytes(),
                      before_sha256=sha256(before),current_sha256=sha256(after))
            execute('revised_tb_bad_fill',['vvp',str(out/'current_revised_tb.vvp'),'+BAD_FILL'],
                    expected=1,marker='fill returns requested word',cwd=out)
            shutil.copyfile(out/'tb_dcache.vcd',out/'revised_tb_bad_fill.vcd')
            # Isolated fault fixtures prove that event waits still reject wrong
            # or absent bus transactions. Production dcache.v remains untouched.
            read='assign bus_mem_re_o = bus_mem_re_r;'
            qualifier='assign bus_load_miss_o = bus_load_miss_r;'
            duplicate="(bus_mem_re_r || ((state == FILL) && (fill_cnt == 1)))"
            fixtures=[
                ('missing_read',[(read,"assign bus_mem_re_o = 1'b0;"),
                                 (qualifier,"assign bus_load_miss_o = 1'b0;")],'request timeout/count mismatch'),
                ('duplicate_read',[(read,'assign bus_mem_re_o = '+duplicate+';'),
                                   (qualifier,'assign bus_load_miss_o = '+duplicate+';')],'unexpected or duplicate bus request'),
                ('wrong_address',[('assign bus_addr_o = bus_addr_r;',"assign bus_addr_o = bus_addr_r ^ 32'h4;")],'transaction address actual='),
                ('wrong_write_data',[('assign bus_wdata_o = bus_wdata_r;',"assign bus_wdata_o = bus_wdata_r ^ 32'h1;")],'transaction write data actual='),
                ('wrong_write_mask',[('assign bus_wmask_o = bus_wmask_r;',"assign bus_wmask_o = bus_wmask_r ^ 4'h1;")],'transaction write mask actual='),
                ('missing_write',[('assign bus_mem_we_o = bus_mem_we_r;',"assign bus_mem_we_o = 1'b0;")],'request timeout/count mismatch')]
            original_cache=variants['current'].read_text(encoding='utf-8')
            for label,replacements,marker in fixtures:
                text=original_cache
                for before,after in replacements:
                    if text.count(before)!=1: raise ValueError('D-cache fault seam changed: '+label)
                    text=text.replace(before,after)
                source=out/('dcache_fixture_'+label+'.v')
                source.write_text(text,encoding='utf-8',newline='\n')
                report.setdefault('negative_fixtures',{})[label]=dict(sha256=sha256(source),changes=replacements)
                exe=compile_tb('revised_tb_'+label,source,'tb_dcache','sim/original_cpu/unit/dcache/tb_dcache.v')
                execute('revised_tb_'+label,['vvp',str(exe)],expected=1,marker=marker,cwd=out)
                shutil.copyfile(out/'tb_dcache.vcd',out/('revised_tb_'+label+'.vcd'))
            for label,flag,marker in [('old_timing_probe','OLD_TIMING_PROBE','old one-cycle miss assumption'),
                                       ('bad_fill','BAD_FILL','CPU load mismatch'),('drop_write','DROP_WRITE','CPU load mismatch')]:
                execute(label,['vvp',str(out/'current_contract.vvp'),'+'+flag],expected=1,marker=marker,cwd=out)
            report['classification']='TB_STALE' if all(r['gate']=='PASS' for r in report['commands']) and all(c['status']=='PASS' for c in report['checks']) else 'INCONCLUSIVE'

        if a.mode in ('all','interrupt'):
            cc=compiler_prefix(a.cc_prefix)
            execute('compiler_version',cc+[a.cc_prefix+'gcc','--version'])
            execute('binutils_version',cc+[a.cc_prefix+'objcopy','--version'])
            def build_irq(label,extra=()):
                stem=out/label
                rel=lambda p: Path(p).relative_to(ROOT).as_posix()
                execute(label+'_build',cc+[a.cc_prefix+'gcc','-march=rv32im_zicsr','-mabi=ilp32',
                    '-nostdlib','-x','assembler-with-cpp','-Wl,-e,_start',*extra,'-T','src/firmware/ascon_rv32/riscv.ld',
                    'sim/board/interrupt_firmware.s','-o',rel(stem.with_suffix('.elf'))])
                execute(label+'_objcopy',cc+[a.cc_prefix+'objcopy','-O','binary',rel(stem.with_suffix('.elf')),rel(stem.with_suffix('.bin'))])
                execute(label+'_hex',python_command()+['src/firmware/ascon_rv32/bin2vhex.py',str(stem.with_suffix('.bin')),
                        str(stem.with_suffix('.hex')),'32','32768'])
                report.setdefault('firmware_sha256',{})[label]=sha256(stem.with_suffix('.bin'))
                return stem.with_suffix('.hex')
            firmware=build_irq('interrupt')
            _,text=execute('irq_symbols',cc+[a.cc_prefix+'nm','-n',(out/'interrupt.elf').relative_to(ROOT).as_posix()])
            syms={name:addr for addr,kind,name in re.findall(r'^([0-9a-fA-F]+)\s+(\w)\s+(\S+)$',text,re.M)}
            args=['+'+key+'='+syms[name] for key,name in [('LOOP','irq_loop'),('DIV','irq_div'),
                  ('LOAD','irq_load'),('BRANCH','irq_branch'),('HANDLER','irq_handler')]]
            rtl=[str(p.relative_to(ROOT)) for p in sorted((ROOT/'src/rtl').glob('*.v')) if p.name not in ('top.v','top_pl_bram.v')]
            rtl += [str(p.relative_to(ROOT)) for p in sorted((ROOT/'src/rtl/ascon').glob('*.v')) if not p.name.endswith('_tb.v')]
            executable=out/'interrupt.vvp'
            compile_command=['iverilog','-g2012','-I','src/rtl','-I','src/rtl/ascon','-s','tb_cpu_interrupt','-o',str(executable)]+rtl+['sim/board/tb_cpu_interrupt.v']
            execute('irq_compile',compile_command)
            coverage=[]
            for case in range(6):
                _,text=execute('irq_case_'+str(case),['vvp',str(executable),'+HEX='+str(firmware),'+CASE='+str(case)]+args,
                               marker='tb_cpu_interrupt PASS case='+str(case),cwd=out)
                result=re.search(r'\[RESULT\] tb_cpu_interrupt PASS (.*)',text)
                if result:
                    coverage.append({k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',result[1])})
            report['interrupt_coverage']=coverage
            check('six_real_timer_handler_mret_cases',len(coverage)==6 and all(r['accepts']==r['mret']==1 for r in coverage))
            execute('irq_no_timer_negative',['vvp',str(executable),'+HEX='+str(firmware),'+CASE=0','+NO_TIMER']+args,
                    expected=1,marker='interrupt acceptance/handler/mret watchdog',cwd=out)
            broken=build_irq('interrupt_no_mret',('-DBROKEN_MRET',))
            execute('irq_no_mret_negative',['vvp',str(executable),'+HEX='+str(broken),'+CASE=0']+args,
                    expected=1,marker='interrupt acceptance/handler/mret watchdog',cwd=out)
            # Negative fixture exists only under build/local. The production CPU
            # is never edited; bypassing the registered guard must be detected.
            original=(ROOT/'src/rtl/cpu_core.v').read_text(encoding='utf-8')
            needle='wire inter_accept_ready = inter_slow_ok_q\n                           && id_ex_inst_valid'
            if original.count(needle)!=1: raise ValueError('guard source changed; review mutation seam')
            mutant=out/'cpu_guard_bypass_fixture.v'
            mutant.write_text(original.replace(needle,'wire inter_accept_ready = id_ex_inst_valid'),encoding='utf-8',newline='\n')
            mutant_command=[str(out/'interrupt_bad_guard.vvp') if x==str(executable) else str(mutant) if x.replace('\\','/')=='src/rtl/cpu_core.v' else x for x in compile_command]
            execute('irq_bad_guard_compile',mutant_command)
            execute('irq_bad_guard_negative',['vvp',str(out/'interrupt_bad_guard.vvp'),'+HEX='+str(firmware),'+CASE=1']+args,
                    expected=1,marker='interrupt accepted without a replayable instruction / during stall',cwd=out)
    except Exception as exc:
        report['error']=str(exc)
        check('runner_execution',False,error=str(exc))
    report['status']='PASS' if all(r['gate']=='PASS' for r in report['commands']) and all(c['status']=='PASS' for c in report['checks']) else 'FAIL'
    report['elapsed_s']=round(time.monotonic()-start,3)
    inputs=[ROOT/'sim/board'/n for n in ('run_targeted_validation.py','tb_dcache_contract.v','tb_cpu_interrupt.v','interrupt_firmware.s')]
    inputs += [ROOT/'sim/original_cpu/unit/dcache/tb_dcache.v',ROOT/'build/timing_tests/tb_dcache_trace.v']
    inputs += list((ROOT/'src/rtl').glob('*.v'))+list((ROOT/'src/rtl/ascon').glob('*.v'))
    report['source_sha256']={str(p.relative_to(ROOT)):sha256(p) for p in inputs}
    write_json(out/'summary.json',report)
    lines=['# Targeted validation: '+report['status'],'','D-cache classification: '+report['classification'],
           '','Legacy failure and negative-test exit codes remain visible below.','',
           '| Test | Actual | Exit | Expected exit | Gate |','|---|---|---|---|---|']
    lines += [f'| {r["name"]} | {r["status"]} | {r["exit_code"]} | {r["expected_exit_code"]} | {r["gate"]} |' for r in report['commands']]
    (out/'summary.md').write_text('\n'.join(lines)+'\n',encoding='utf-8',newline='\n')
    print(report['status'],report['classification'],out/'summary.json')
    return 0 if report['status']=='PASS' else 1


if __name__=='__main__':
    sys.exit(main())
