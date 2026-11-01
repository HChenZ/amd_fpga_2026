#!/usr/bin/env python3
import sys
from pathlib import Path


def hex_to_coe(hex_path, coe_path):
    words = []
    for line in Path(hex_path).read_text().splitlines():
        word = line.strip()
        if not word or word.startswith("@"):
            continue
        words.append(word)

    if not words:
        raise ValueError(f"{hex_path} has no hex data")

    with Path(coe_path).open("w", newline="\n") as f:
        f.write("memory_initialization_radix=16;\n")
        f.write("memory_initialization_vector=\n")
        for index, word in enumerate(words):
            terminator = ";" if index == len(words) - 1 else ","
            f.write(f"{word}{terminator}\n")


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} input.hex output.coe", file=sys.stderr)
        return 1

    try:
        hex_to_coe(sys.argv[1], sys.argv[2])
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    print(f"Done! Created COE: {sys.argv[2]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
