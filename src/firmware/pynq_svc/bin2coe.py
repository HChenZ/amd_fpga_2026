#!/usr/bin/env python3
"""bin2coe.py —— 把扁平二进制转成 Vivado blk_mem_gen 的 .coe 初始化文件。

格式与工程里既有的 ascon_*.coe 一致：
    memory_initialization_radix=16;
    memory_initialization_vector=
    XXXXXXXX,
    ...
    XXXXXXXX;

用法: bin2coe.py input.bin output.coe [pad_words]
默认 pad_words = 32768（32 bit × 32768 = 128 KiB BRAM 深度）。
"""
import sys


def bin_to_coe(bin_path, coe_path, pad_words=32768):
    with open(bin_path, "rb") as f:
        data = f.read()
    while len(data) % 4 != 0:
        data += b"\x00"
    words = [int.from_bytes(data[i:i + 4], "little") for i in range(0, len(data), 4)]
    n = len(words)
    if pad_words > n:
        words += [0] * (pad_words - n)
    with open(coe_path, "w", newline="\n") as f:
        f.write("memory_initialization_radix=16;\n")
        f.write("memory_initialization_vector=\n")
        for i, w in enumerate(words):
            last = (i == len(words) - 1)
            f.write("{:08X}{}\n".format(w, ";" if last else ","))
    print("Done! {} words (padded to {}) -> {}".format(n, pad_words, coe_path))


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: {} input.bin output.coe [pad_words]".format(sys.argv[0]))
        sys.exit(1)
    pad = int(sys.argv[3]) if len(sys.argv) >= 4 else 32768
    bin_to_coe(sys.argv[1], sys.argv[2], pad)
