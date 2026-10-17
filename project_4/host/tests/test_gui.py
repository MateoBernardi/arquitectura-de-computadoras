"""Tests de la GUI (gui.py) — sin FPGA, sin pyserial y sin binutils.

Correr:  python3 -m unittest discover -s tests   (desde project_4/host)

La FPGA se simula con un puerto serie falso (mismo protocolo que debug_unit.v)
y el ensamblador de binutils se reemplaza por una lista fija de palabras, asi
se puede probar la ventana y el flujo Conectar / Cargar / Step / Refresh en la PC.
"""
import os
import sys
import types
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
HOST = os.path.dirname(HERE)
for _p in (HOST, HERE):
    if _p not in sys.path:
        sys.path.insert(0, _p)

import debug_protocol as dp          # noqa: E402

# --------------------------------------------------------------- datos falsos
PROG = [0x00500093, 0x00A00113, 0x002081B3]      # addi x1,x0,5 / addi x2,x0,10 / add x3,x1,x2
LISTING = "00000000 <_start>:\n   0: 00500093  addi x1,x0,5\n"


def make_dump(pc=0x8):
    """Dump valido del bus de debug: 22 de cabecera + 32 regs + 32 dmem."""
    w = [0] * (dp.DBG_REGS + 32 + 32)
    w[0] = pc                                     # PC actual
    w[1], w[2] = 0x4, PROG[0]                     # IF/ID: pc, instr
    w[3] = 0b1                                    # ID/EX: reg_write
    w[4] = 1 | (2 << 5) | (3 << 10)               # rs1=x1, rs2=x2, rd=x3
    w[5], w[6], w[7], w[8] = 0x4, 5, 10, 0        # pc, rdata1, rdata2, imm
    w[13] = 0b1                                   # EX: stall
    w[14] = 1 | (2 << 4)                          # EX/MEM: reg_write, wb=mem
    w[15], w[16], w[17], w[18] = 0x0F, 10, 3, 0xAB
    w[19], w[20], w[21] = 1, 0x0F, 3              # MEM/WB
    for i in range(32):
        w[dp.DBG_REGS + i] = i                    # reg i = i
    for i in range(32):
        w[dp.DBG_DMEM + i] = 0x100 + i            # dmem[i]
    return w


class FakeFPGA:
    """Puerto serie falso: responde como la debug unit de la FPGA."""

    def __init__(self, dump=None, halt_on_step=False):
        self.rx = b""
        self.timeout = 1
        self.baudrate = 19200
        self.written = b""
        self.loaded = []
        self.dump_words = dump if dump is not None else make_dump()
        self.halt_on_step = halt_on_step
        self.closed = False

    def reset_input_buffer(self):
        pass

    def close(self):
        self.closed = True

    def write(self, data):
        self.written += data
        cmd = data[:1]
        if cmd == b"L":
            n = int.from_bytes(data[1:3], "little")
            self.loaded.append([int.from_bytes(data[3 + 4 * i:7 + 4 * i], "little") for i in range(n)])
            self.rx += dp.RSP_OK
        elif cmd in (dp.CMD_STEP, dp.CMD_RUN):
            self.rx += dp.RSP_HALT if (self.halt_on_step and cmd == dp.CMD_STEP) else dp.RSP_OK
        elif cmd in (dp.CMD_PAUSE, dp.CMD_RESET):
            self.rx += dp.RSP_OK
        elif cmd == dp.CMD_DUMP:
            self.rx += len(self.dump_words).to_bytes(2, "little")
            for v in self.dump_words:
                self.rx += (v & 0xFFFFFFFF).to_bytes(4, "little")

    def read(self, n):
        out, self.rx = self.rx[:n], self.rx[n:]
        return out


class _MessageBox:
    """Reemplazo de tkinter.messagebox: no abre dialogos modales."""
    errors = []

    @classmethod
    def showerror(cls, title, msg):
        cls.errors.append((title, msg))


def _conectar(app, gui, fpga):
    """Instala la FPGA falsa y conecta la GUI (helper de los tests de flujo)."""
    if app.ser:
        app.disconnect()
    fake = types.ModuleType("serial")
    fake.Serial = lambda *a, **k: fpga
    sys.modules["serial"] = fake
    app.port.config(values=["COM_TEST"])
    app.port.set("COM_TEST")
    app.toggle_connect()


# --------------------------------------------------------------------- tests
class GuiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        try:
            import tkinter as tk
        except Exception as e:                        # pragma: no cover
            raise unittest.SkipTest(f"sin tkinter: {e}")
        cls.tk = tk
        try:
            cls.root = tk.Tk()
        except tk.TclError as e:                      # pragma: no cover
            raise unittest.SkipTest(f"sin display para Tk: {e}")
        cls.root.geometry("1000x640+40+40")
        cls.root.deiconify()

        import gui
        cls.gui = gui
        cls.app = gui.App(cls.root)
        cls.root.update_idletasks()
        cls.root.update()

    @classmethod
    def tearDownClass(cls):
        try:
            cls.root.destroy()
        except Exception:
            pass

    # ------------------------------------------------------------- estructura
    def test_titulo(self):
        self.assertEqual(self.root.title(), "RISC-V debug")

    def test_botones_son_redondeados(self):
        g, app = self.gui, self.app
        self.assertEqual(sorted(app.buttons), ["Actualizar", "Ensamblar y cargar", "Pause",
                                               "Reset CPU", "Run", "Step"])
        for nombre, b in app.buttons.items():
            self.assertIsInstance(b, g.RoundedButton, nombre)
            self.assertEqual(b._state, "disabled", f"{nombre}: deberia arrancar deshabilitado")
        self.assertIsInstance(app.btn_conn, g.RoundedButton)
        self.assertEqual(app.btn_conn._prefix, g.CONNECT_PREFIX)

    def test_iconos(self):
        app = self.app
        self.assertEqual(app.buttons["Step"]._prefix, "\u25b6|")
        for nombre in app.buttons:
            self.assertTrue(app.buttons[nombre]._prefix, f"{nombre}: sin icono")
        self.assertEqual(app.buttons["Run"]._style, "Accent.TButton")
        self.assertEqual(app.buttons["Ensamblar y cargar"]._style, "Accent.TButton")

    def test_tema_oscuro(self):
        from tkinter import ttk
        g = self.gui
        self.assertEqual(self.app.editor.cget("bg"), g.BG_DARK)
        # el fondo de la ventana raiz tambien debe ser oscuro (si no, se ve
        # un borde gris #f0f0f0 en los margenes alrededor de los paneles)
        self.assertEqual(str(self.root.cget("bg")).lower(), g.BG)
        st = ttk.Style(self.root)
        self.assertEqual((st.lookup("TFrame", "background") or "").lower(), g.BG)
        self.assertEqual((st.lookup("TLabel", "foreground") or "").lower(), g.FG)
        self.assertEqual((st.lookup("Treeview.Heading", "foreground") or "").lower(), g.CYAN)
        if g._HAS_PIL:
            self.assertIn("Rounded.Tab", st.element_names())

    def test_barra_de_titulo_dwm(self):
        res = self.gui._titlebar_dark(self.root)
        self.assertIsInstance(res, list)
        self.assertNotIn("error", [k for k, _ in res])

    # ------------------------------------------------------------------ boton
    def test_click_de_boton(self):
        g = self.gui
        hits = []
        b = g.RoundedButton(self.root, text="Prueba", prefix="\u25b6", command=lambda: hits.append(1))
        b.pack()
        self.root.update_idletasks()
        b._on_press(None)
        b._on_release(None)
        self.assertEqual(hits, [1])
        b.configure(text="Otro")                    # el icono debe sobrevivir
        self.assertEqual(b._prefix, "\u25b6")
        b.configure(state="disabled")
        b._on_press(None)
        b._on_release(None)
        self.assertEqual(hits, [1], "deshabilitado no debe disparar el comando")
        b.destroy()

    # ------------------------------------------------- flujo completo simulado
    def test_flujo_conectar_cargar_step(self):
        gui, app = self.gui, self.app
        _MessageBox.errors = []
        gui.messagebox = _MessageBox
        from assemble import Assembled
        gui.assemble_text = lambda src, max_words=None: Assembled(PROG, LISTING)

        fpga = FakeFPGA()
        try:
            _conectar(self.app, self.gui, fpga)
            self.assertIsNotNone(app.link, "no quedo link tras conectar")
            self.assertEqual(_MessageBox.errors, [])
            self.assertIn("Conectado", app.status.get())
            for b in app.buttons.values():
                self.assertEqual(b._state, "normal", "los botones deberian habilitarse")

            app.assemble_and_load()
            self.assertEqual(fpga.loaded, [PROG], "no llego el programa por el puerto")
            self.assertIn("00500093", app.hexview.get("1.0", "end"))

            app.step()
            self.assertEqual(_MessageBox.errors, [])
            self.assertIn("Step", app.status.get())
        finally:
            self.app.disconnect()
            sys.modules.pop("serial", None)

    def test_flujo_refresh_muestra_estado(self):
        gui, app = self.gui, self.app
        _MessageBox.errors = []
        gui.messagebox = _MessageBox
        fpga = FakeFPGA(dump=make_dump(pc=0x8))
        try:
            _conectar(app, gui, fpga)
            app.refresh()
            self.assertEqual(_MessageBox.errors, [])

            stages = app.stages.get("1.0", "end")
            self.assertIn("IF/ID", stages)
            self.assertIn("addi", stages)                  # 0x00500093
            self.assertIn("0x00000008", stages)            # PC

            self.assertEqual(app.regtree.item("3", "values")[2], "0x00000003")
            self.assertIn("0000", app.dmemview.get("1.0", "end"))
        finally:
            app.disconnect()
            sys.modules.pop("serial", None)


if __name__ == "__main__":
    unittest.main()
