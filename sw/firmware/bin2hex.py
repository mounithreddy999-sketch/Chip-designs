import sys

if len(sys.argv) != 3:
    print(f"Usage: {sys.argv[0]} <input.bin> <output.hex>")
    sys.exit(1)

with open(sys.argv[1], 'rb') as f:
    data = f.read()

with open(sys.argv[2], 'w') as f:
    for i in range(0, len(data), 4):
        chunk = data[i:i+4]
        # Pad with 0s if chunk is less than 4 bytes
        chunk = chunk + b'\x00' * (4 - len(chunk))
        # PicoRV32 uses little endian
        word = int.from_bytes(chunk, 'little')
        f.write(f"{word:08x}\n")
