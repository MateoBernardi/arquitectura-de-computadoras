#!/usr/bin/env python3
"""Muestra de forma legible lo que encontró SymbiYosys en una tarea.

    python3 show_trace.py [--brief] <directorio_de_tarea>

- Si la tarea FALLÓ: qué propiedad se rompió y el contraejemplo
  (los valores de las señales del módulo de propiedades, ciclo a ciclo).
- Si fue un cover: un ejemplo concreto por cada cover alcanzado
  (con --brief, solo la lista de covers alcanzados y no alcanzados).

Solo muestra las señales del módulo de nivel superior (el de propiedades),
no las internas del DUT, y oculta las señales auxiliares de Yosys (*_EN).
"""
import os
import re
import sys


def parse_vcd(path):
    """Devuelve (señales, pasos): señales = [(nombre, ancho)], pasos = [{nombre: valor}]."""
    ids, order, depth = {}, [], 0
    steps, cur = [], {}
    with open(path) as f:
        for line in f:
            tok = line.split()
            if not tok:
                continue
            if tok[0] == '$scope':
                depth += 1
            elif tok[0] == '$upscope':
                depth -= 1
            elif tok[0] == '$var' and depth == 1:
                width, code, name = int(tok[2]), tok[3], tok[4]
                if (name.endswith('_EN') or name.startswith('smt_')
                        or '$' in name or name.startswith('\\')):
                    continue        # señales auxiliares de Yosys
                ids[code] = (name, width)
                order.append((name, width))
            elif tok[0].startswith('#'):
                if cur:
                    steps.append(dict(cur))
            elif tok[0].startswith('b') and len(tok) == 2 and tok[1] in ids:
                bits = tok[0][1:]
                cur[ids[tok[1]][0]] = None if re.search('[xz]', bits) else int(bits, 2)
            elif len(tok) == 1 and tok[0][0] in '01' and tok[0][1:] in ids:
                cur[ids[tok[0][1:]][0]] = int(tok[0][0])
    if cur:
        steps.append(dict(cur))
    # El último "#t" de smtbmc repite el estado final: deduplicar.
    while len(steps) > 1 and steps[-1] == steps[-2]:
        steps.pop()
    return order, steps


def fmt(value, width, name=''):
    if value is None:
        return 'x'
    if width == 1:
        return str(value)
    if width == 2:
        return f"2'b{value:02b}"
    if width == 5 and re.search(r'(^|_)(rd|rs\d?)($|_)', name):   # índices de registro
        return f'x{value}'
    if width <= 8:
        return f"{width}'b{value:0{width}b}"
    return f'0x{value:0{(width + 3) // 4}x}'


REG = lambda r: f'x{r}'


def sx(v, bits):
    return v - (1 << bits) if v >> (bits - 1) else v


def disasm(w):
    """Desensambla una palabra RV32I (para leer programas de contraejemplos)."""
    op, rd, f3 = w & 0x7F, (w >> 7) & 31, (w >> 12) & 7
    rs1, rs2, f7 = (w >> 15) & 31, (w >> 20) & 31, w >> 25
    imm_i = sx(w >> 20, 12)
    imm_s = sx(((w >> 25) << 5) | ((w >> 7) & 31), 12)
    imm_b = sx(((w >> 31) << 12) | (((w >> 7) & 1) << 11) | (((w >> 25) & 63) << 5)
               | (((w >> 8) & 15) << 1), 13)
    imm_j = sx(((w >> 31) << 20) | (((w >> 12) & 255) << 12) | (((w >> 20) & 1) << 11)
               | (((w >> 21) & 1023) << 1), 21)
    if op == 0x33:
        name = {(0, 0): 'add', (0, 32): 'sub', (1, 0): 'sll', (2, 0): 'slt', (3, 0): 'sltu',
                (4, 0): 'xor', (5, 0): 'srl', (5, 32): 'sra', (6, 0): 'or', (7, 0): 'and'}.get((f3, f7))
        return f'{name} {REG(rd)}, {REG(rs1)}, {REG(rs2)}' if name else '¿R inválida?'
    if op == 0x13:
        if f3 in (1, 5):
            name = {(1, 0): 'slli', (5, 0): 'srli', (5, 32): 'srai'}.get((f3, f7))
            return f'{name} {REG(rd)}, {REG(rs1)}, {rs2}' if name else '¿shift inválido?'
        name = {0: 'addi', 2: 'slti', 3: 'sltiu', 4: 'xori', 6: 'ori', 7: 'andi'}[f3]
        return f'{name} {REG(rd)}, {REG(rs1)}, {imm_i}'
    if op == 0x03:
        name = {0: 'lb', 1: 'lh', 2: 'lw', 4: 'lbu', 5: 'lhu'}.get(f3, '¿load?')
        return f'{name} {REG(rd)}, {imm_i}({REG(rs1)})'
    if op == 0x23:
        name = {0: 'sb', 1: 'sh', 2: 'sw'}.get(f3, '¿store?')
        return f'{name} {REG(rs2)}, {imm_s}({REG(rs1)})'
    if op == 0x63:
        name = {0: 'beq', 1: 'bne', 4: 'blt', 5: 'bge', 6: 'bltu', 7: 'bgeu'}.get(f3, '¿branch?')
        return f'{name} {REG(rs1)}, {REG(rs2)}, {imm_b:+d}'
    if op == 0x6F:
        return f'jal {REG(rd)}, {imm_j:+d}'
    if op == 0x67:
        return f'jalr {REG(rd)}, {imm_i}({REG(rs1)})'
    if op == 0x37:
        return f'lui {REG(rd)}, 0x{w >> 12:x}'
    if op == 0x17:
        return f'auipc {REG(rd)}, 0x{w >> 12:x}'
    if op == 0x0F:
        return 'fence'
    if op == 0x73:
        return {0x00000073: 'ecall', 0x00100073: 'ebreak'}.get(w, 'system (¿?)')
    return '(opcode inválido)'


def print_trace(path):
    order, steps = parse_vcd(path)
    names = {n for n, _ in order}
    # El VCD de smtbmc tiene dos instantes por ciclo (clk=1 y clk=0):
    # nos quedamos con uno por ciclo.
    if 'clk' in names:
        steps = [s for s in steps if s.get('clk') == 1]
        order = [(n, w) for n, w in order if n != 'clk']
    wide = [(n, w) for n, w in order if w > 64]
    narrow = [(n, w) for n, w in order if w <= 64]
    name_w = max(len(n) for n, _ in narrow)
    header = ' ' * (name_w + 2) + ''.join(f'ciclo {i:<7}' for i in range(len(steps)))
    print(header)
    for name, width in narrow:
        cells = ''.join(f'{fmt(s.get(name), width, name):<13}' for s in steps)
        print(f'{name:<{name_w}}  {cells}')
    # Señales anchas (ej.: el programa): se muestran una vez, por palabras.
    for name, width in wide:
        value = steps[0].get(name) if steps else None
        if value is None:
            continue
        print(f'{name}:')
        for i in range(width // 32):
            word = (value >> (32 * i)) & 0xFFFFFFFF
            print(f'    [0x{4 * i:02x}] {word:08x}   {disasm(word)}')


def source_line(taskdir, loc):
    """loc = 'archivo.sv:70.9-70.72' → texto de esa línea en src/."""
    m = re.match(r'(.+?):(\d+)\.', loc)
    if not m:
        return ''
    path = os.path.join(taskdir, 'src', m.group(1))
    try:
        with open(path) as f:
            return f.readlines()[int(m.group(2)) - 1].strip()
    except (OSError, IndexError):
        return ''


def main():
    args = sys.argv[1:]
    brief = '--brief' in args
    taskdir = [a for a in args if a != '--brief'][0].rstrip('/')
    with open(os.path.join(taskdir, 'logfile.txt')) as f:
        log = f.read()

    # ---- Fallas: solo el contraejemplo real (basecase), no el de inducción
    for m in re.finditer(r'summary: counterexample trace(?: \[basecase\])?: (\S+)\n'
                         r'((?:.*summary:\s+failed assertion .*\n)+)', log):
        trace = m.group(1)
        for name, loc in re.findall(r'failed assertion (\S+) at (\S+)', m.group(2)):
            print(f'✘ falla {name.split(".")[-1]}')
            print(f'    {source_line(taskdir, loc)}')
        print('  contraejemplo:')
        # El log da la ruta relativa a donde se corrió sby: nos quedamos con
        # la parte que está dentro del directorio de la tarea.
        inside = trace.split(os.path.basename(taskdir) + '/', 1)[-1]
        print_trace(os.path.join(taskdir, inside))
        print()

    # ---- Inducción fallida (resultado UNKNOWN): el contraejemplo arranca en
    #      un estado ARBITRARIO, que puede no ser alcanzable desde el reset.
    if not re.search(r'counterexample trace(?: \[basecase\])?:', log):
        for m in re.finditer(r'summary: counterexample trace \[induction\]: (\S+)\n'
                             r'((?:.*summary:\s+failed assertion .*\n)+)', log):
            for name, loc in re.findall(r'failed assertion (\S+) at (\S+)', m.group(2)):
                print(f'? la inducción no pudo probar {name.split(".")[-1]}')
                print(f'    {source_line(taskdir, loc)}')
            print('  contraejemplo de INDUCCIÓN (el ciclo 0 es un estado arbitrario,')
            print('  quizás inalcanzable desde el reset; ver pipeline_control/README.md):')
            inside = m.group(1).split(os.path.basename(taskdir) + '/', 1)[-1]
            print_trace(os.path.join(taskdir, inside))
            print()

    # ---- Covers alcanzados: un ejemplo por cada uno
    covers = re.findall(r'Reached cover statement in step (\d+) at \S+: (\S+)\n'
                        r'.*Writing trace to VCD file: (\S+)', log)
    for step, name, trace in sorted(covers, key=lambda c: c[1]):
        print(f'✔ cover {name} (alcanzado en el paso {step})')
        if not brief:
            print_trace(os.path.join(taskdir, trace))
            print()
    for name in sorted(set(re.findall(r'Unreached cover statement at \S+: (\S+)', log))):
        print(f'✘ cover {name} NO alcanzable')


if __name__ == '__main__':
    main()
