#!/usr/bin/env python3
"""Convert a flat binary to a 32-bit little-endian Verilog $readmemh hex file.

Usage: bin2vhex.py input.bin output.hex [32|64] [pad_words]
  pad_words: optional, pad the hex to this many words with zeros (matches the
             hardware BRAM depth so $readmemh fills every word).
"""
import sys

def bin_to_vhex(bin_path, hex_path, width_bits, pad_words=0):
    width_bytes = width_bits // 8
    with open(bin_path, 'rb') as f:
        data = f.read()
    while len(data) % width_bytes != 0:
        data += b'\x00'
    nwords = len(data) // width_bytes
    with open(hex_path, 'w') as f:
        for i in range(0, len(data), width_bytes):
            chunk = data[i:i + width_bytes]
            val = int.from_bytes(chunk, byteorder='little')
            f.write("{:0{}X}\n".format(val, width_bytes * 2))
        for _ in range(max(0, pad_words - nwords)):
            f.write("{:0{}X}\n".format(0, width_bytes * 2))
    print("Done! {} words -> {} (padded to {})".format(nwords, hex_path, pad_words))

if __name__ == "__main__":
    if len(sys.argv) < 4:
        print("Usage: {} input.bin output.hex [32|64] [pad_words]".format(sys.argv[0]))
        sys.exit(1)
    pad = int(sys.argv[4]) if len(sys.argv) >= 5 else 0
    bin_to_vhex(sys.argv[1], sys.argv[2], int(sys.argv[3]), pad)
