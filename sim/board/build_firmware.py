"""Build existing firmware with its existing flags/startup/linker/converter, into a fresh local directory."""
import argparse
import json
from pathlib import Path
import re
import struct
import sys

from common import ROOT, compiler_prefix, git, local_output, python_command, run, sha256, write_json
from coe import BASE, BRAM_BYTES, convert


def inspect_elf(path, symbols, binary):
    data = path.read_bytes()
    if data[:7] != b'\x7fELF\x01\x01\x01':
        raise ValueError('expected ELF32 little endian')
    header = struct.unpack_from('<16sHHIIIIIHHHHHH', data)
    if header[1:3] != (2, 243) or header[4] != BASE:
        raise ValueError('expected RISC-V executable at reset PC 0x10000000')
    if header[7] & 0xf:  # RVC/float/RVE/TSO are outside RV32IM_Zicsr build contract.
        raise ValueError('unexpected ELF ISA/ABI flags')
    segments = []
    for i in range(header[10]):
        ph = struct.unpack_from('<IIIIIIII',data,header[5]+i*header[9])
        if ph[0] != 1:
            continue
        _,offset,vaddr,paddr,filesz,memsz,flags,align = ph
        if vaddr != paddr or not BASE <= vaddr <= vaddr+memsz <= BASE+BRAM_BYTES or filesz>memsz:
            raise ValueError('invalid BRAM load segment or differing load/run address')
        segments.append(dict(address=hex(vaddr),file_bytes=filesz,memory_bytes=memsz,flags=flags))
    if not segments:
        raise ValueError('ELF has no load segment')
    shoff, shsize, shnum, shstr = header[6], header[11], header[12], header[13]
    sections = [struct.unpack_from('<IIIIIIIIII', data, shoff+i*shsize) for i in range(shnum)]
    names = sections[shstr]
    names = data[names[4]:names[4]+names[5]]
    allocated = []
    reconstructed = bytearray()
    for s in sections:
        if not s[2] & 2 or not s[5]:
            continue
        name = names[s[0]:].split(b'\0', 1)[0].decode('ascii')
        if s[3] < BASE or s[3] + s[5] > BASE + BRAM_BYTES:
            raise ValueError('allocated ELF section outside BRAM')
        allocated.append(dict(name=name, address=hex(s[3]), bytes=s[5], nobits=s[1] == 8))
        if s[1] != 8:
            end = s[3] - BASE + s[5]
            if len(reconstructed) < end:
                reconstructed.extend(bytes(end-len(reconstructed)))
            reconstructed[s[3]-BASE:end] = data[s[4]:s[4]+s[5]]
    if bytes(reconstructed) != binary:
        raise ValueError('BIN differs from ELF allocated file-backed sections')
    sym = {name: int(addr, 16) for addr, kind, name in
           re.findall(r'^([0-9a-fA-F]+)\s+(\w)\s+(\S+)$', symbols, re.M)}
    if sym.get('_start') != BASE or sym.get('_stack_top') != BASE+BRAM_BYTES-16:
        raise ValueError('startup or stack placement mismatch')
    if not BASE <= sym['_sdata'] <= sym['_edata'] <= sym['_sbss'] <= sym['_ebss'] < sym['_stack_top']:
        raise ValueError('data/BSS/stack overlap or invalid ordering')
    headroom = sym['_stack_top'] - sym['_ebss']
    if headroom < 4096:
        raise ValueError('less than 4 KiB available below stack')
    return dict(status='PASS', entry=hex(header[4]), sections=allocated,load_segments=segments,
                symbols={k: hex(sym[k]) for k in ('_start','_sdata','_edata','_sbss','_ebss','_stack_top')},
                stack_headroom_bytes=headroom, dynamic_stack_usage='NOT_MEASURED',
                bss_initialization='existing crt0.S zero loop; runtime tested by CPU regression')


def build(mode, out, prefix):
    out = local_output(out)
    out.mkdir(parents=True, exist_ok=False)
    fw = ROOT / 'src/firmware' / ('ascon_rv32' if mode == 'sw' else f'ascon_{mode}_rv32')
    report = dict(mode=mode, status='FAIL', source_head=git('rev-parse','HEAD'),
                  evidence_kind='build_validation', commands=[], compiler_prefix=prefix)
    cc = compiler_prefix(prefix)
    stem = out / f'ascon_{mode}'
    rel = lambda p: Path(p).relative_to(ROOT).as_posix()

    def execute(command, label):
        record, output = run(command, timeout=180, log=out / f'{label}.log')
        report['commands'].append(record)
        if record['status'] != 'PASS':
            report['status'] = record['status']
            raise RuntimeError(f'{label}: {record["status"]}; see {record["log"]}')
        return output

    try:
        report['compiler_version'] = execute(cc+[prefix+'gcc','--version'], 'compiler').splitlines()[0]
        report['binutils_version'] = execute(cc+[prefix+'objcopy','--version'], 'binutils').splitlines()[0]
        flags = ['-march=rv32im_zicsr','-mabi=ilp32','-O2','-ffreestanding','-nostdlib',
                 '-fno-builtin','-fno-stack-protector','-msmall-data-limit=0','-Wall','-Wextra',
                 '-I'+rel(fw), '-Iascon/ascon_c/aead']
        report['flags'] = flags
        sources = [fw / name for name in ('crt0.S','main.c','uart.c','libc_min.c')]
        execute(cc+[prefix+'gcc']+flags+['-T',rel(fw/'riscv.ld')]+[rel(s) for s in sources]+
                ['-lgcc','-o',rel(stem.with_suffix('.elf'))], 'compile')
        execute(cc+[prefix+'objcopy','-O','binary',rel(stem.with_suffix('.elf')),rel(stem.with_suffix('.bin'))], 'objcopy')
        symbols = execute(cc+[prefix+'nm','-n',rel(stem.with_suffix('.elf'))], 'symbols')
        execute(cc+[prefix+'readelf','-W','-a',rel(stem.with_suffix('.elf'))], 'readelf')
        execute(cc+[prefix+'objdump','-d',rel(stem.with_suffix('.elf'))], 'disassembly')
        execute(cc+[prefix+'size',rel(stem.with_suffix('.elf'))], 'size')
        execute(python_command()+[rel(fw/'bin2vhex.py'),rel(stem.with_suffix('.bin')),
                rel(stem.with_suffix('.hex')),'32','32768'], 'hex')
        report['elf_layout'] = inspect_elf(stem.with_suffix('.elf'), symbols, stem.with_suffix('.bin').read_bytes())
        report['bram'] = convert(stem.with_suffix('.bin'), stem.with_suffix('.hex'), stem.with_suffix('.coe'))
        report['outputs'] = {suffix: dict(path=str(stem.with_suffix('.'+suffix)),
            bytes=stem.with_suffix('.'+suffix).stat().st_size, sha256=sha256(stem.with_suffix('.'+suffix)))
            for suffix in ('elf','bin','hex','coe')}
        inputs = list(fw.glob('*')) + list((ROOT/'ascon/ascon_c/aead').glob('*'))
        report['input_sha256'] = {rel(p):sha256(p) for p in inputs if p.is_file()}
        report['status'] = 'PASS'
    except Exception as exc:
        report['error'] = str(exc)
    write_json(out/'build.json', report)
    return report


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--cc-prefix', default='riscv64-unknown-elf-')
    p.add_argument('--mode', choices=('all','sw','hw','ise'), default='all')
    args = p.parse_args()
    out = local_output(args.out)
    out.mkdir(parents=True, exist_ok=False)
    reports = [build(mode, out/mode, args.cc_prefix) for mode in
               (('sw','hw','ise') if args.mode == 'all' else (args.mode,))]
    write_json(out/'builds.json', reports)
    for report in reports:
        print(report['mode'], report['status'], report.get('error',''))
    return 1 if any(r['status']=='FAIL' for r in reports) else (2 if any(r['status']=='BLOCKED' for r in reports) else 0)


if __name__ == '__main__':
    sys.exit(main())
