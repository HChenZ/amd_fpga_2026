"""Validate BIN/readmemh/COE byte equality for 32-bit x 32768 little-endian BRAM."""
import argparse
from pathlib import Path
import re

BRAM_BYTES = 128 * 1024
BASE = 0x10000000


def image_words(data, capacity=BRAM_BYTES):
    if not data or len(data) > capacity or capacity % 4:
        raise ValueError('empty image, invalid capacity or BRAM overflow')
    padded = data.ljust(capacity, b'\0')
    return [int.from_bytes(padded[i:i+4], 'little') for i in range(0, capacity, 4)]


def parse_hex(text):
    tokens = text.split()
    if not tokens or any(not re.fullmatch(r'[0-9a-fA-F]{8}', token) for token in tokens):
        raise ValueError('expected one plain 32-bit hexadecimal word per token')
    return [int(token, 16) for token in tokens]


def parse_coe(text):
    match = re.fullmatch(r'\s*memory_initialization_radix\s*=\s*16\s*;\s*'
                         r'memory_initialization_vector\s*=\s*([\s\S]+);\s*', text, re.I)
    if not match:
        raise ValueError('invalid COE header or terminator')
    tokens = [part.strip() for part in match[1].split(',')]
    if any(not re.fullmatch(r'[0-9a-fA-F]{8}', part) for part in tokens):
        raise ValueError('invalid COE word')
    return [int(part, 16) for part in tokens]


def convert(binary, vhex, output):
    data = Path(binary).read_bytes()
    expected = image_words(data)
    if parse_hex(Path(vhex).read_text()) != expected:
        raise ValueError('HEX differs from padded BIN (word order/endian/content/size)')
    text = 'memory_initialization_radix=16;\nmemory_initialization_vector=\n'
    text += ',\n'.join(f'{word:08X}' for word in expected) + ';\n'
    Path(output).write_text(text, encoding='ascii', newline='\n')
    words = parse_coe(Path(output).read_text())
    reconstructed = b''.join(word.to_bytes(4, 'little') for word in words)
    if reconstructed != data.ljust(BRAM_BYTES, b'\0'):
        raise ValueError('COE/BIN round trip differs')
    return dict(status='PASS', base=f'0x{BASE:08x}', bytes=len(data),
                capacity_bytes=BRAM_BYTES, words=len(words), word_bits=32,
                byte_order='little', word_order='ascending byte address', padding='zero',
                first_word=f'{words[0]:08X}', bin_hex_coe_equal=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary', type=Path)
    parser.add_argument('hex', type=Path)
    parser.add_argument('coe', type=Path)
    args = parser.parse_args()
    from common import local_output
    print(convert(args.binary, args.hex, local_output(args.coe)))
