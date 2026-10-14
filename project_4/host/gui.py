#!/usr/bin/env python3
"""
gui.py - GUI de la debug unit del RISC-V (tkinter + pyserial).

Escribir assembly RV32I, "Ensamblar y cargar" (binutils RISC-V -> palabras -> trama 'L'),
y controlar el CPU: Step / Run / Pause / Reset. Muestra etapas del pipeline, registros y dmem.
Requiere: pyserial, tkinter y binutils RISC-V (ver assemble.py).
"""
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

from assemble import AssemblerError, INSTALL_HINT, assemble_text, hex_listing
from debug_protocol import ABI, DebugLink, ProtocolError, decode_dump, disasm, format_stages

IMEM_WORDS = 256                      # 2**IMEM_ADDR_W / 4 (top_riscv.v)
SAMPLE = """# Suma 1..5 en x2 y la guarda en dmem[0]
        addi x1, x0, 1
        addi x2, x0, 0
        addi x3, x0, 6
loop:   bge  x1, x3, done
        add  x2, x2, x1
        addi x1, x1, 1
        j    loop
done:   sw   x2, 0(x0)
        ebreak
"""


class App:
    def __init__(self, root):
        self.root = root
        root.title("RISC-V debug")
        self.ser = None
        self.link = None
        self.running = False
        self.prev_regs = [0] * 32
        self._build()

    # ------------------------------------------------------------------ UI
    def _build(self):
        top = ttk.Frame(self.root, padding=4)
        top.pack(fill="x")
        ttk.Label(top, text="Puerto").pack(side="left")
        self.port = ttk.Combobox(top, width=38, values=self._ports())
        self.port.pack(side="left", padx=4)
        ttk.Button(top, text="↻", width=3, command=lambda: self.port.config(values=self._ports())).pack(side="left")
        ttk.Label(top, text="Baud").pack(side="left", padx=(8, 0))
        self.baud = ttk.Entry(top, width=7)
        self.baud.insert(0, "19200")
        self.baud.pack(side="left", padx=4)
        self.btn_conn = ttk.Button(top, text="Conectar", command=self.toggle_connect)
        self.btn_conn.pack(side="left", padx=4)

        bar = ttk.Frame(self.root, padding=(4, 0))
        bar.pack(fill="x")
        self.buttons = {}
        for name, cmd in (("Ensamblar y cargar", self.assemble_and_load), ("Step", self.step),
                          ("Run", self.run), ("Pause", self.pause), ("Reset CPU", self.reset),
                          ("Actualizar", self.refresh)):
            b = ttk.Button(bar, text=name, command=cmd, state="disabled")
            b.pack(side="left", padx=2, pady=4)
            self.buttons[name] = b
        ttk.Button(bar, text="Abrir…", command=self.open_file).pack(side="right", padx=2)
        ttk.Button(bar, text="Guardar…", command=self.save_file).pack(side="right", padx=2)

        panes = ttk.PanedWindow(self.root, orient="horizontal")
        panes.pack(fill="both", expand=True, padx=4, pady=4)

        left = ttk.Notebook(panes)
        self.editor = tk.Text(left, width=48, height=28, font=("monospace", 10), undo=True)
        self.editor.insert("1.0", SAMPLE)
        self.hexview = tk.Text(left, width=48, height=28, font=("monospace", 10), state="disabled")
        left.add(self.editor, text="Assembly")
        left.add(self.hexview, text="Hex generado")
        panes.add(left, weight=1)

        right = ttk.Notebook(panes)
        self.stages = tk.Text(right, width=84, height=28, font=("monospace", 9), state="disabled")
        right.add(self.stages, text="Pipeline")
        regs = ttk.Frame(right)
        self.regtree = ttk.Treeview(regs, columns=("reg", "abi", "hex", "dec"), show="headings", height=32)
        for c, w in (("reg", 50), ("abi", 60), ("hex", 100), ("dec", 100)):
            self.regtree.heading(c, text=c)
            self.regtree.column(c, width=w, anchor="w")
        self.regtree.tag_configure("changed", background="#ffe9a8")
        for i in range(32):
            self.regtree.insert("", "end", iid=str(i), values=(f"x{i}", ABI[i], "0x00000000", "0"))
        self.regtree.pack(fill="both", expand=True)
        right.add(regs, text="Registros")
        self.dmemview = tk.Text(right, width=84, height=28, font=("monospace", 9), state="disabled")
        right.add(self.dmemview, text="Memoria de datos")
        panes.add(right, weight=2)

        self.status = tk.StringVar(value="Desconectado")
        ttk.Label(self.root, textvariable=self.status, relief="sunken", anchor="w").pack(fill="x")

    @staticmethod
    def _ports():
        try:
            from serial.tools import list_ports
            return [p.device for p in list_ports.comports()]
        except Exception:
            return []

    def _set_text(self, widget, text):
        widget.config(state="normal")
        widget.delete("1.0", "end")
        widget.insert("1.0", text)
        widget.config(state="disabled")

    def _enable(self, on):
        for b in self.buttons.values():
            b.config(state="normal" if on else "disabled")

    # ------------------------------------------------------------ conexion
    def toggle_connect(self):
        if self.ser:
            self.disconnect()
            return
        try:
            import serial
            self.ser = serial.Serial(self.port.get(), int(self.baud.get()), bytesize=8, parity="N",
                                     stopbits=1, timeout=1)
            self.ser.reset_input_buffer()
        except Exception as e:
            self.ser = None
            messagebox.showerror("Puerto serie", str(e))
            return
        self.link = DebugLink(self.ser)
        self.btn_conn.config(text="Desconectar")
        self._enable(True)
        self.status.set(f"Conectado a {self.port.get()}")

    def disconnect(self):
        self.running = False
        if self.ser:
            self.ser.close()
        self.ser = self.link = None
        self.btn_conn.config(text="Conectar")
        self._enable(False)
        self.status.set("Desconectado")

    def _guard(self, fn):
        try:
            return fn()
        except (ProtocolError, AssemblerError, ValueError) as e:
            self.running = False
            self.status.set(f"Error: {e}")
            messagebox.showerror("Error", str(e))
        except Exception as e:                        # serie desconectado, etc.
            self.disconnect()
            messagebox.showerror("Error de comunicacion", str(e))

    # ------------------------------------------------------------ acciones
    def assemble_and_load(self):
        def go():
            self.running = False
            result = assemble_text(self.editor.get("1.0", "end"), IMEM_WORDS)
            self._set_text(self.hexview, result.listing + "\n" + hex_listing(result.words))
            self.link.load(result.words)
            self.status.set(f"Cargadas {len(result.words)} instrucciones; CPU detenido en PC=0")
            self.refresh()
        try:
            self._guard(go)
        except Exception:
            pass

    def step(self):
        def go():
            self.running = False
            self.status.set("Step" if self.link.step() else "El CPU esta en halt")
            self.refresh()
        self._guard(go)

    def run(self):
        def go():
            if not self.link.run():
                self.status.set("El CPU esta en halt (Reset CPU o recargar)")
                return
            self.running = True
            self.status.set("Ejecutando…")
            self.root.after(100, self._poll)
        self._guard(go)

    def _poll(self):
        if not self.running or not self.link:
            return

        def go():
            if self.link.poll_halt(0.0):
                self.running = False
                self.status.set("Halt (ebreak/ecall)")
                self.refresh()
            else:
                self.root.after(100, self._poll)
        self._guard(go)

    def pause(self):
        def go():
            halted = self.link.pause()
            self.running = False
            self.status.set("Halt" if halted else "Pausado")
            self.refresh()
        self._guard(go)

    def reset(self):
        def go():
            self.running = False
            self.link.reset()
            self.status.set("CPU reseteado (PC=0, registros en 0)")
            self.refresh()
        self._guard(go)

    def refresh(self):
        def go():
            if self.running:
                self.link.pause()
                self.running = False
                self.status.set("Pausado para leer el estado")
            d = decode_dump(self.link.dump())
            self._show(d)
        self._guard(go)

    def _show(self, d):
        text = format_stages(d)
        text += "\n\nIF/ID: " + disasm(d["if_id"]["inst"], d["if_id"]["pc"])
        self._set_text(self.stages, text)
        for i, v in enumerate(d["regs"]):
            changed = v != self.prev_regs[i]
            self.regtree.item(str(i), values=(f"x{i}", ABI[i], f"0x{v:08x}", str(v - (1 << 32) if v >> 31 else v)),
                              tags=("changed",) if changed else ())
        self.prev_regs = d["regs"]
        lines = [f"[{4 * i:04x}] 0x{v:08x}  {v}" for i, v in enumerate(d["dmem"])]
        self._set_text(self.dmemview, "\n".join(lines))

    # ------------------------------------------------------------ archivos
    def open_file(self):
        path = filedialog.askopenfilename(filetypes=[("Assembly", "*.s *.S *.asm"), ("Todos", "*")])
        if path:
            with open(path) as f:
                self.editor.delete("1.0", "end")
                self.editor.insert("1.0", f.read())

    def save_file(self):
        path = filedialog.asksaveasfilename(defaultextension=".s")
        if path:
            with open(path, "w") as f:
                f.write(self.editor.get("1.0", "end"))


def main():
    root = tk.Tk()
    App(root)
    root.mainloop()


if __name__ == "__main__":
    main()
