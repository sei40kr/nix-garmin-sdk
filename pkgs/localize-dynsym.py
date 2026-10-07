"""Turn exported symbols of an ELF executable into local dynamic symbols.

Garmin's binaries statically embed FreeType, libpng and libjpeg and export
those symbols. Shared libraries loaded into the process (libfreetype, cairo,
gdk-pixbuf, ...) then bind to the embedded copies instead of their own, which
crashes as soon as the versions differ (e.g. FreeType's TT_Load_Glyph calling
the executable's TT_New_Context).

glibc ignores STB_LOCAL entries during symbol lookup, so marking the exports
local hides them from other objects. The executable itself calls its embedded
copies directly, which this script verifies by refusing to touch symbols that
are referenced by a dynamic relocation.

Usage: localize-dynsym.py FILE REGEX
"""

import re
import struct
import sys

SHT_RELA, SHT_DYNSYM, SHT_REL = 4, 11, 9
STB_LOCAL, STB_GLOBAL, STB_WEAK = 0, 1, 2
SHN_UNDEF = 0


def main():
    path, pattern = sys.argv[1], re.compile(sys.argv[2])
    with open(path, "rb") as f:
        data = bytearray(f.read())

    if data[:4] != b"\x7fELF" or data[4] != 2 or data[5] != 1:
        sys.exit(f"{path}: not a little-endian ELF64 file")

    e_shoff, = struct.unpack_from("<Q", data, 0x28)
    e_shentsize, e_shnum = struct.unpack_from("<HH", data, 0x3A)
    sections = [
        struct.unpack_from("<IIQQQQIIQQ", data, e_shoff + i * e_shentsize)
        for i in range(e_shnum)
    ]

    dynsym_idx = next(i for i, s in enumerate(sections) if s[1] == SHT_DYNSYM)
    _, _, _, _, sym_off, sym_size, strtab_idx, _, _, sym_entsize = sections[dynsym_idx]
    str_off = sections[strtab_idx][4]

    def name_at(offset):
        end = data.index(b"\0", str_off + offset)
        return data[str_off + offset : end].decode()

    # Symbols used by dynamic relocations must stay visible.
    relocated = set()
    for s in sections:
        if s[1] in (SHT_RELA, SHT_REL) and s[6] == dynsym_idx:
            entsize = s[9]
            for off in range(s[4], s[4] + s[5], entsize):
                r_info, = struct.unpack_from("<Q", data, off + 8)
                relocated.add(r_info >> 32)

    changed = 0
    for idx in range(sym_size // sym_entsize):
        off = sym_off + idx * sym_entsize
        st_name, st_info, _, st_shndx = struct.unpack_from("<IBBH", data, off)
        bind, typ = st_info >> 4, st_info & 0xF
        if st_shndx == SHN_UNDEF or bind not in (STB_GLOBAL, STB_WEAK):
            continue
        name = name_at(st_name)
        if not pattern.match(name):
            continue
        if idx in relocated:
            sys.exit(f"{path}: {name} is referenced by a relocation, refusing to hide it")
        data[off + 4] = (STB_LOCAL << 4) | typ
        changed += 1

    with open(path, "wb") as f:
        f.write(data)
    print(f"{path}: localized {changed} dynamic symbols matching {pattern.pattern}")


if __name__ == "__main__":
    main()
