#!/usr/bin/env python3
import argparse
import re
from pathlib import Path


HEX_RE = re.compile(r"^[0-9a-fA-F_]+$")


def parse_hex_words(path, width):
    max_digits = width // 4
    words = []
    for lineno, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw_line.split("//", 1)[0].split("#", 1)[0].strip()
        if not line:
            continue

        if line.startswith("@"):
            raise ValueError(
                f"{path}:{lineno}: address directives like {line!r} are not supported"
            )

        line = line.replace("0x", "").replace("0X", "").replace("_", "")
        if not HEX_RE.match(line):
            raise ValueError(f"{path}:{lineno}: invalid hex word {raw_line!r}")
        if len(line) > max_digits:
            raise ValueError(
                f"{path}:{lineno}: word is wider than {width} bits: {raw_line!r}"
            )

        words.append(line.zfill(max_digits).lower())

    return words


def write_coe(words, output_path):
    if not words:
        raise ValueError("input contains no hex words")

    lines = [
        "memory_initialization_radix=16;",
        "memory_initialization_vector=",
    ]

    for index, word in enumerate(words):
        suffix = ";" if index == len(words) - 1 else ","
        lines.append(f"{word}{suffix}")

    output_path.write_text("\n".join(lines) + "\n", encoding="ascii")


def main():
    parser = argparse.ArgumentParser(
        description="Convert a $readmemh-style 32-bit hex file to Vivado .coe."
    )
    parser.add_argument("input", type=Path, help="input .hex/.txt file")
    parser.add_argument(
        "output",
        type=Path,
        nargs="?",
        help="output .coe file, defaults to input name with .coe suffix",
    )
    parser.add_argument(
        "--width",
        type=int,
        choices=(32, 64),
        default=32,
        help="input/output word width in bits",
    )
    args = parser.parse_args()

    output = args.output if args.output else args.input.with_suffix(".coe")
    words = parse_hex_words(args.input, args.width)
    write_coe(words, output)
    print(f"wrote {len(words)} {args.width}-bit words to {output}")


if __name__ == "__main__":
    main()
