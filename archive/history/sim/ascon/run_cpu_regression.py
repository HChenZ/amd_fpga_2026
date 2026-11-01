"""Build and execute the real RV32 SoC; Windows uses the WSL cross compiler.

No behavioral crypto replacement: all three images run production firmware/RTL.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


def main():
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--mode', choices=['sw', 'hw', 'ise'], required=True)
    p.add_argument('--security', action='store_true')
    p.add_argument('--pynq-p0', action='store_true', help='explicit frozen P0 SoC/MMIO, without PUF key override')
    p.add_argument('--legacy', action='store_true')
    p.add_argument('--label', default='after')
    p.add_argument('--stall', action='store_true')
    p.add_argument('--reset', action='store_true')
    p.add_argument('--cc-prefix', default='riscv64-unknown-elf-')
    p.add_argument('--iverilog', default='iverilog')
    p.add_argument('--vvp', default='vvp')
    a = p.parse_args()
    os.chdir(ROOT)
    name = a.mode + ('_security' if a.security else '') + '_' + a.label
    out = Path('build/local/key_audit') / name
    out.mkdir(parents=True, exist_ok=True)
    evidence = Path('data/ascon/results/key_lifecycle')
    evidence.mkdir(parents=True, exist_ok=True)
    report = dict(kind='simulation', mode=a.mode, security=a.security, commands=[],
                  source_head=subprocess.check_output(['git','rev-parse','HEAD'], text=True).strip())
    logs = []

    def run(cmd, timeout=1200):
        r = subprocess.run(cmd, capture_output=True, timeout=timeout)
        text = (r.stdout + r.stderr).decode('utf-8', errors='replace').replace('\r\n','\n')
        report['commands'].append(dict(command=cmd, exit_code=r.returncode))
        logs.append('$ ' + ' '.join(cmd) + '\n' + text + f'\nEXIT {r.returncode}\n')
        if r.returncode:
            raise RuntimeError(text[-3000:])
        return text

    # Windows: WSL cross compiler for the original workflow; a native Windows
    # cc-prefix (drive-letter path, e.g. xpack riscv-none-elf) runs directly.
    prefix = (['wsl', '-d', 'Ubuntu', '--']
              if (os.name == 'nt' and not a.cc_prefix.startswith(('C:/', 'C:\\')))
              else [])
    fw = Path('src/firmware') / ('ascon_rv32' if a.mode == 'sw' else f'ascon_{a.mode}_rv32')
    try:
        run(prefix + [a.cc_prefix+'gcc', '--version'])
        run([a.iverilog, '-V'])
        main_c = 'sim/ascon/key_lifecycle_firmware.c' if a.security else (fw/'main.c').as_posix()
        flags = ['-march=rv32im_zicsr','-mabi=ilp32','-O2','-ffreestanding','-nostdlib',
                 '-fno-builtin','-fno-stack-protector','-msmall-data-limit=0','-Wall','-Wextra',
                 '-I'+fw.as_posix(), '-Iascon/ascon_c/aead', '-Ibuild/local/key_audit',
                 '-DTEST_'+a.mode.upper()]
        if a.legacy:
            flags += ['-DKEY_AUDIT_LEGACY']
        elf = (out/'firmware.elf').as_posix()
        run(prefix + [a.cc_prefix+'gcc'] + flags + ['-T', (fw/'riscv.ld').as_posix(),
            (fw/'crt0.S').as_posix(), main_c, (fw/'uart.c').as_posix(),
            (fw/'libc_min.c').as_posix(), '-lgcc','-o',elf])
        run(prefix+[a.cc_prefix+'objcopy','-O','binary',elf,(out/'firmware.bin').as_posix()])
        dis = run(prefix+[a.cc_prefix+'objdump','-d',elf])
        (out/'firmware.dis').write_text(dis, encoding='utf-8', newline="\n")
        report['elf_sha256'] = hashlib.sha256(Path(elf).read_bytes()).hexdigest()
        report['size'] = run(prefix+[a.cc_prefix+'size',elf])
        run([sys.executable, (fw/'bin2vhex.py').as_posix(), (out/'firmware.bin').as_posix(),
             (out/'firmware.hex').as_posix(), '32','32768'])
        rtl = [s.as_posix() for s in sorted(Path('src/rtl').glob('*.v'))
               if s.name not in ('top.v','top_pl_bram.v')]
        rtl += [s.as_posix() for s in sorted(Path('src/rtl/ascon').glob('*.v')) if not s.name.endswith('_tb.v')]
        if a.pynq_p0:
            rtl = [s for s in rtl if Path(s).name not in ('soc_top.v','ascon_mmio.v')]
            rtl += [str(s) for s in Path('board/vivado_zynq7000_xc7z020_pynq/rtl_p0').glob('*.v')]
            report['source_set'] = 'pynq rtl_p0 (no PUF)'
        inputs = rtl+[main_c,'sim/ascon/tb_ascon_sw.v','sim/ascon/axi_slave_bram.v']
        inputs += [s.as_posix() for s in fw.iterdir() if s.is_file()]
        inputs += [s.as_posix() for s in Path('ascon/ascon_c/aead').iterdir() if s.is_file()]
        if a.security: inputs += ['build/local/key_audit/key_cases.h']
        report['source_hashes'] = {s: hashlib.sha256(Path(s).read_bytes()).hexdigest() for s in inputs}
        run([a.iverilog,'-g2012','-I','src/rtl','-I','src/rtl/ascon','-s','tb_ascon_sw',
             '-o',(out/'soc.vvp').as_posix()] + rtl + ['sim/ascon/axi_slave_bram.v','sim/ascon/tb_ascon_sw.v'])
        extra = (['+HOLD_ISE'] if a.stall else []) + (['+RESET_ISE'] if a.reset else [])
        sim = run([a.vvp,(out/'soc.vvp').as_posix(),'+HEX='+(out/'firmware.hex').as_posix()] + extra)
        if '[RESULT] tb_ascon_sw PASS' not in sim or 'FAIL' in sim:
            raise RuntimeError('missing PASS or firmware FAIL')
        if a.stall and 'PASS injected CPU hold across ISE completion' not in sim:
            raise RuntimeError('requested hold injection did not execute')
        if a.reset and 'PASS injected reset during ISE' not in sim:
            raise RuntimeError('requested reset injection did not execute')
        report['status'] = 'PASS'
        print(sim)
    except Exception as exc:
        report.update(status='FAIL', error=str(exc))
        print(str(exc))
    finally:
        (evidence/(name+'.json')).write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8', newline="\n")
        (evidence/(name+'.log')).write_text('\n'.join(logs), encoding='utf-8', newline="\n")
    return 0 if report['status']=='PASS' else 1


if __name__ == '__main__':
    sys.exit(main())
