"""Tests del host: python3 -m unittest discover -s tests  (desde project_4/host)."""
import os
import re
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, HERE)

import debug_protocol as dp  # noqa: E402
import rv32i_model as model  # noqa: E402


def norm(tok):
    try:
        return int(tok, 0)
    except ValueError:
        return tok.lower()


class FakeSerial:
    """Serie simulado: write() encola la respuesta que daria la FPGA."""
    baudrate = 19200

    def __init__(self, replies):
        self.replies, self.rx, self.written, self.timeout = replies, b"", b"", 1

    def write(self, data):
        self.written += data
        self.rx += self.replies.pop(0)

    def read(self, n):
        out, self.rx = self.rx[:n], self.rx[n:]
        return out


class ProtocolTests(unittest.TestCase):
    def test_encode_load(self):
        self.assertEqual(dp.encode_load([0x00500093, 0x13]),
                         b"L\x02\x00" + bytes([0x93, 0x00, 0x50, 0x00, 0x13, 0, 0, 0]))

    def test_link(self):
        words = list(range(dp.DBG_DMEM + 4))
        payload = len(words).to_bytes(2, "little") + b"".join(w.to_bytes(4, "little") for w in words)
        link = dp.DebugLink(FakeSerial([b"K", b"K", b"H", b"K", payload, b"HK"]))
        link.load([1, 2])
        self.assertTrue(link.step())
        self.assertFalse(link.step())            # halt
        link.reset()
        self.assertEqual(link.dump(), words)
        self.assertTrue(link.pause())            # el halt llego antes de la pausa

    def test_errors(self):
        with self.assertRaises(dp.ProtocolError):
            dp.DebugLink(FakeSerial([b"E"])).load([1])
        with self.assertRaises(dp.ProtocolError):
            dp.DebugLink(FakeSerial([b""])).run()

    def test_decode_dump(self):
        w = [0] * 86
        w[0], w[13] = 0x20, 0b10_01_1_0_0_1_0_0_1   # redirect (bit 3) etc.
        w[13] = 1 | (1 << 3) | (2 << 8) | (1 << 10)
        w[22 + 5], w[54] = 0xAB, 0xCD
        d = dp.decode_dump(w)
        self.assertEqual((d["pc"], d["regs"][5], d["dmem"][0]), (0x20, 0xAB, 0xCD))
        self.assertEqual((d["ex"]["stall"], d["ex"]["redirect"], d["ex"]["fwd_a"], d["ex"]["fwd_b"]),
                         (1, 1, "mem", "wb"))
        self.assertEqual(len(d["dmem"]), 32)

    def test_disasm_roundtrip(self):
        src = open(os.path.join(HERE, "pipeline_test.s")).read()
        words, lines = model.assemble(src)
        for i, (w, line) in enumerate(zip(words, lines)):
            if re.match(r"(beq|bne|blt|bge|jal)\b", line):
                continue                           # los destinos son etiquetas
            got = re.sub(r"[,()]", " ", dp.disasm(w, 4 * i)).split()
            want = re.sub(r"[,()]", " ", line).split()
            self.assertEqual([norm(t) for t in got], [norm(t) for t in want], line)


if __name__ == "__main__":
    unittest.main()
