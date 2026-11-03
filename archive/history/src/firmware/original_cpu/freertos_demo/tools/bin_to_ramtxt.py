#!/usr/bin/env python3
import argparse
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(
        description="Convert a raw RISC-V little-endian binary into one 32-bit word per line for $readmemh."
    )
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--depth", type=int, default=32768, help="maximum number of 32-bit words")
    args = parser.parse_args()

    data = args.input.read_bytes()
    if len(data) > args.depth * 4:
        raise SystemExit(f"binary is {len(data)} bytes, larger than {args.depth * 4} byte RAM image")

    if len(data) % 4:
        data += b"\x00" * (4 - (len(data) % 4))

    lines = []
    for offset in range(0, len(data), 4):
        word = int.from_bytes(data[offset : offset + 4], "little")
        lines.append(f"{word:08x}")

    args.output.write_text("\n".join(lines) + "\n", encoding="ascii")


if __name__ == "__main__":
    main()
