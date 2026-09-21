#!/usr/bin/env python3
import sys

def bin_to_vhex_flexible(bin_path, hex_path, width_bits):
    width_bytes = width_bits // 8
    with open(bin_path, 'rb') as f:
        data = f.read()
    
    # 根据位宽填充对齐
    while len(data) % width_bytes != 0:
        data += b'\x00'
    
    with open(hex_path, 'w') as f:
        for i in range(0, len(data), width_bytes):
            chunk = data[i:i+width_bytes]
            val = int.from_bytes(chunk, byteorder='little')
            # 根据位宽格式化输出
            fmt = f"{{:0{width_bytes*2}X}}\n"
            f.write(fmt.format(val))
    
    print(f"Done! Created {width_bits}-bit Hex with {len(data)//width_bytes} lines.")

if __name__ == "__main__":
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} input.bin output.hex [32|64]")
        sys.exit(1)
    bin_to_vhex_flexible(sys.argv[1], sys.argv[2], int(sys.argv[3]))