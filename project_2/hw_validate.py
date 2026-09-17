#!/usr/bin/env python3
"""
Hardware validation for the UART+ALU project (TP2), Nexys4 DDR.

Sends random (opcode, op_A, op_B) triples over the real serial port,
reads back the one-byte result, and checks it against a Python
reimplementation of alu_tp1's arithmetic -- same idea as model.vh in
the Verilog testbenches, just running against real silicon instead
of a simulator.

Requires: pip install pyserial

Before running:
  - Flash the bitstream and make sure the board is connected via USB.
  - Find the UART port: `ls /dev/ttyUSB*` (Linux) right after plugging
    in -- the Nexys4 DDR enumerates two ports (JTAG + UART); if unsure
    which is which, unplug/replug and see which two appear, then try
    the higher-numbered one first.
  - Set PORT and BAUD below to match your board and your `top`
    instance's BAUD_RATE parameter (19200 if left at the default).
  - If your alu_ops.vh uses different funct values than the standard
    MIPS ones below, update the OP_* constants to match.
"""

import random
import serial

PORT     = "/dev/serial/by-id/usb-Digilent_Digilent_USB_Device_210292742127-if01-port0" 
BAUD     = 19200            # must match top's BAUD_RATE parameter
N_TESTS  = 200
TIMEOUT  = 2.0              # seconds to wait for the result byte

# Standard MIPS funct codes -- match these to your actual alu_ops.vh
OP_ADD, OP_SUB = 0b100000, 0b100010
OP_AND, OP_OR  = 0b100100, 0b100101
OP_XOR         = 0b100110
OP_SRA, OP_SRL = 0b000011, 0b000010
OP_NOR         = 0b100111
OPS = [OP_ADD, OP_SUB, OP_AND, OP_OR, OP_XOR, OP_SRA, OP_SRL, OP_NOR]
OP_NAMES = {OP_ADD: "ADD", OP_SUB: "SUB", OP_AND: "AND", OP_OR: "OR",
            OP_XOR: "XOR", OP_SRA: "SRA", OP_SRL: "SRL", OP_NOR: "NOR"}


def to_signed8(x):
    x &= 0xFF
    return x - 256 if x >= 128 else x


def golden_alu(a_raw, b_raw, op):
    """Mirrors alu_tp1.v's combinational logic exactly, including how
    Verilog treats the shift amount as an unsigned bit pattern and
    saturates when it's >= the operand width."""
    a_signed, b_signed = to_signed8(a_raw), to_signed8(b_raw)
    a_u, b_u = a_raw & 0xFF, b_raw & 0xFF

    if op == OP_ADD: return (a_signed + b_signed) & 0xFF
    if op == OP_SUB: return (a_signed - b_signed) & 0xFF
    if op == OP_AND: return a_u & b_u
    if op == OP_OR:  return a_u | b_u
    if op == OP_XOR: return a_u ^ b_u
    if op == OP_SRA:
        if b_u >= 8: return 0xFF if (a_u & 0x80) else 0x00
        return (a_signed >> b_u) & 0xFF
    if op == OP_SRL:
        if b_u >= 8: return 0x00
        return (a_u >> b_u) & 0xFF
    if op == OP_NOR: return (~(a_u | b_u)) & 0xFF
    return 0


def main():
    ser = serial.Serial(PORT, BAUD, timeout=TIMEOUT)
    errors = 0

    for i in range(N_TESTS):
        op = random.choice(OPS)
        a = random.randint(0, 255)
        b = random.randint(0, 255)
        expected = golden_alu(a, b, op)

        ser.write(bytes([op, a, b]))
        resp = ser.read(1)

        if len(resp) == 0:
            print(f"FAIL {i}: no response  op={OP_NAMES[op]} a={a:#04x} b={b:#04x}")
            errors += 1
            continue

        got = resp[0]
        ok = (got == expected)
        if not ok:
            errors += 1
        print(f"{'PASS' if ok else 'FAIL'} {i}: op={OP_NAMES[op]:<3} a={a:#04x} b={b:#04x} "
              f"-> got={got:#04x} expected={expected:#04x}")

    print(f"\n{N_TESTS - errors}/{N_TESTS} passed")
    ser.close()


if __name__ == "__main__":
    main()
