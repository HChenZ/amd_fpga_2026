"""Build isolated RV32 DMA firmware; native prefix or WSL wrapper via --cc-prefix."""
import argparse
import hashlib
import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--cc-prefix', default='riscv64-unknown-elf-')
    p.add_argument('--out', default='build/local/pynq_dma_svc')
    a = p.parse_args()
    out = ROOT / a.out
    out.mkdir(parents=True, exist_ok=True)
    records = []

    def run(cmd, destination=None):
        r = subprocess.run(cmd, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
        records.append({'command': cmd, 'exit_code': r.returncode})
        if destination:
            destination.write_bytes(r.stdout)
        else:
            print(r.stdout.decode(errors='replace'))
        if r.returncode:
            raise RuntimeError('build command failed')
        return r.stdout

    common = 'src/firmware/ascon_hw_rv32/'
    fw = 'src/firmware/pynq_dma_svc/'
    elf = out / 'dma_svc.elf'
    version = run([a.cc_prefix + 'gcc', '--version']).decode(errors='replace').splitlines()[0]
    run([a.cc_prefix + 'gcc', '-march=rv32im_zicsr', '-mabi=ilp32', '-O2',
         '-ffreestanding', '-nostdlib', '-fno-builtin', '-fno-stack-protector',
         '-msmall-data-limit=0', '-Wall', '-Wextra', '-Iascon/ascon_c/aead',
         '-T', common + 'riscv.ld', common + 'crt0.S', common + 'libc_min.c',
         fw + 'main.c', fw + 'ascon_modes.c', '-lgcc', '-o', str(elf)])
    binary = out / 'dma_svc.bin'
    run([a.cc_prefix + 'objcopy', '-O', 'binary', str(elf), str(binary)])
    disasm = run([a.cc_prefix + 'objdump', '-d', str(elf)], out / 'dma_svc.disasm.txt').decode()
    words = [int(x, 16) for x in re.findall(r'^\s*[0-9a-f]+:\s+([0-9a-f]{8})\s', disasm, re.M)]
    custom = [x for x in words if x & 0x7f == 0x0b]
    assert 0x200b in custom and 0x300b in custom, 'ISE instructions missing'
    assert any((x >> 12) & 7 == 0 for x in custom) and any((x >> 12) & 7 == 1 for x in custom)
    run([sys.executable, common + 'bin2vhex.py', str(binary), str(out / 'dma_svc.hex'), '32', '32768'])
    run([sys.executable, 'src/firmware/pynq_svc/bin2coe.py', str(binary), str(out / 'dma_svc.coe'), '32768'])
    hashes = {f.name: hashlib.sha256(f.read_bytes()).hexdigest() for f in out.glob('dma_svc.*')}
    metadata = {'compiler': version, 'commands': records, 'sha256': hashes,
                'custom0_count': len(custom), 'p12_count': custom.count(0x200b), 'p8_count': custom.count(0x300b)}
    source_paths = [ROOT/fw/'main.c', ROOT/fw/'ascon_modes.c',
                    ROOT/'src/firmware/pynq_svc/ascon_modes.c', ROOT/'src/firmware/pynq_svc/svc.h']
    source_paths += [ROOT/common/x for x in ('crt0.S','libc_min.c','riscv.ld')]
    source_paths += list((ROOT/'ascon/ascon_c/aead').glob('*.h'))
    source_paths += list((ROOT/'ascon/ascon_c/aead').glob('*.c'))
    metadata['source_sha256'] = {f.relative_to(ROOT).as_posix():hashlib.sha256(f.read_bytes()).hexdigest()
                                 for f in source_paths}
    (out / 'build.json').write_text(json.dumps(metadata, indent=2), encoding='utf-8')
    print(json.dumps(metadata, indent=2))


if __name__ == '__main__':
    main()
