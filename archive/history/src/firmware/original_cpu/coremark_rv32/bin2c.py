import sys
from pathlib import Path

def main():
    if len(sys.argv) < 2:
        print("usage: python bin2h.py <input.bin> [output.h] [array_name]")
        sys.exit(1)

    input_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2]) if len(sys.argv) >= 3 else Path("riscv_prog.h")
    array_name = sys.argv[3] if len(sys.argv) >= 4 else "program_bin"

    data = input_path.read_bytes()

    lines = []
    lines.append(f"unsigned char {array_name}[] = {{")

    for i in range(0, len(data), 12):
        chunk = data[i:i+12]
        line = ", ".join(f"0x{b:02x}" for b in chunk)
        if i + 12 < len(data):
            lines.append(f"    {line},")
        else:
            lines.append(f"    {line}")

    lines.append("};")
    lines.append(f"unsigned int {array_name}_len = {len(data)};")
    lines.append("")

    output_path.write_text("\n".join(lines), encoding="utf-8")
    print(f"generated {output_path} from {input_path}, {len(data)} bytes")

if __name__ == "__main__":
    main()
