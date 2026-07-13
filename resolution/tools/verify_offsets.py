#!/usr/bin/env python3
"""Offline checks that BR RVAs still match libblackrussia-client.so."""
from __future__ import annotations
import struct
import sys
from pathlib import Path

def main() -> int:
    so_path = Path(sys.argv[1] if len(sys.argv) > 1 else
                   "apk-analysis/official/launcher-libs/lib/arm64-v8a/libblackrussia-client.so")
    data = so_path.read_bytes()
    e_phoff = struct.unpack_from("<Q", data, 32)[0]
    e_phentsize = struct.unpack_from("<H", data, 54)[0]
    e_phnum = struct.unpack_from("<H", data, 56)[0]

    def in_image(rva: int) -> bool:
        for i in range(e_phnum):
            off = e_phoff + i * e_phentsize
            if struct.unpack_from("<I", data, off)[0] != 1:
                continue
            p_vaddr = struct.unpack_from("<Q", data, off + 16)[0]
            p_memsz = struct.unpack_from("<Q", data, off + 40)[0]
            if p_vaddr <= rva < p_vaddr + p_memsz:
                return True
        return False

    def u32(off: int) -> int:
        return struct.unpack_from("<I", data, off)[0]

    checks = [
        ("nav ldrb +0x3b8", (u32(0x15BE708) & 0xFFC00000) == 0x39400000 and ((u32(0x15BE708) >> 10) & 0xFFF) == 0x3B8),
        ("nav add +0x394", (u32(0x15BE70C) & 0xFFC00000) == 0x91000000 and ((u32(0x15BE70C) >> 10) & 0xFFF) == 0x394),
        ("HasPos +0x14", (u32(0x15C6D00) & 0xFFC00000) == 0x39400000 and ((u32(0x15C6D00) >> 10) & 0xFFF) == 0x14),
        ("ctor mode store", (u32(0x15BAF48) & 0xFFC00000) == 0x39000000 and ((u32(0x15BAF48) >> 10) & 0xFFF) == 0x3B8),
        ("pool slot in image", in_image(0x33CE110)),
        ("empty nav in image", in_image(0x33B6068)),
        ("sentinel in image", in_image(0x2005A88)),
        ("local pos table in image", in_image(0x3197BD0)),
    ]
    ok = True
    for name, good in checks:
        print(("OK" if good else "FAIL"), name)
        ok = ok and good
    print("VERIFY", "PASS" if ok else "FAIL")
    return 0 if ok else 1

if __name__ == "__main__":
    raise SystemExit(main())
