"""
assemble.py - ensamblador RV32I: wrapper de binutils (as + ld + objcopy), sin ensamblador propio.

Instalacion en Ubuntu/Debian:   sudo apt install binutils-riscv64-unknown-elf
(sirve cualquier prefijo: riscv64-unknown-elf-, riscv32-unknown-elf-, riscv64-linux-gnu-,
riscv-none-elf-). Soporta etiquetas, pseudo-instrucciones (li, mv, j, ret, ...) y nombres ABI.
El programa se enlaza en la direccion 0 (el PC arranca en 0): solo .text, sin .data.
"""
import os
import shutil
import subprocess
import tempfile
from collections import namedtuple

PREFIXES = ("riscv64-unknown-elf-", "riscv32-unknown-elf-", "riscv-none-elf-",
            "riscv64-linux-gnu-", "riscv-none-embed-")
INSTALL_HINT = "sudo apt install binutils-riscv64-unknown-elf"

Assembled = namedtuple("Assembled", "words listing")


class AssemblerError(Exception):
    pass


def find_prefix():
    for p in PREFIXES:
        if shutil.which(p + "as") and shutil.which(p + "ld") and shutil.which(p + "objcopy"):
            return p
    raise AssemblerError(f"no se encontro el ensamblador RISC-V (as/ld/objcopy). Instalar con: {INSTALL_HINT}")


def _run(cmd, what):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise AssemblerError(f"{what}:\n{(r.stderr or r.stdout).strip()}")
    return r.stdout


def assemble_text(source, max_words=None):
    """Ensambla texto assembly. Devuelve Assembled(words, listing)."""
    p = find_prefix()
    with tempfile.TemporaryDirectory() as tmp:
        s, o, elf, binf = (os.path.join(tmp, n) for n in ("prog.s", "prog.o", "prog.elf", "prog.bin"))
        with open(s, "w") as f:
            f.write(source if source.endswith("\n") else source + "\n")
        _run([p + "as", "-march=rv32i", "-mabi=ilp32", "-o", o, s], "error de ensamblado")
        _run([p + "ld", "-m", "elf32lriscv", "-Ttext=0", "-e", "0", "-o", elf, o], "error de enlace")
        _run([p + "objcopy", "-O", "binary", elf, binf], "objcopy")
        with open(binf, "rb") as f:
            data = f.read()
        data += bytes(-len(data) % 4)
        words = [int.from_bytes(data[i:i + 4], "little") for i in range(0, len(data), 4)]
        listing = ""
        if shutil.which(p + "objdump"):
            listing = _run([p + "objdump", "-d", "-M", "no-aliases,numeric", elf], "objdump")
    if max_words is not None and len(words) > max_words:
        raise AssemblerError(f"el programa tiene {len(words)} instrucciones y la memoria admite {max_words}")
    return Assembled(words, listing)


def assemble_file(path, max_words=None):
    with open(path) as f:
        return assemble_text(f.read(), max_words)


def hex_listing(words):
    """Una palabra por linea con su direccion (formato $readmemh + comentario)."""
    return "".join(f"{w:08x}  // 0x{4 * i:04x}\n" for i, w in enumerate(words))
