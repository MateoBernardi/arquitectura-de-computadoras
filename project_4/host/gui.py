#!/usr/bin/env python3
"""
gui.py - GUI de la debug unit del RISC-V (tkinter + pyserial).

Escribir assembly RV32I, "Ensamblar y cargar" (binutils RISC-V -> palabras -> trama 'L'),
y controlar el CPU: Step / Run / Pause / Reset. Muestra etapas del pipeline, registros y dmem.

Tema oscuro (paleta Dracula):
  - botones redondeados dibujados a mano (Canvas), con icono y texto en negrita;
  - solapas de los Notebook con esquinas redondeadas (requiere Pillow; sin el son planas);
  - barra de titulo oscura/coloreada en Windows (API DWM; en otros SO no hace nada).

Requiere: pyserial, tkinter y binutils RISC-V (ver assemble.py).
"""
import sys
import tkinter as tk
from tkinter import filedialog, messagebox, ttk
from tkinter import font as tkfont

try:
    from PIL import Image, ImageDraw, ImageTk
    _HAS_PIL = True
except Exception:                       # sin Pillow -> solapas planas
    _HAS_PIL = False

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

# ------------------------------------------------------------------ paleta
# (estilo Dracula: agradable a la vista y muy usado en IDEs)
BG      = "#282a36"   # fondo general
BG_DARK = "#21222c"   # fondo de campos / editores
PANEL   = "#44475a"   # paneles, solapas, seleccion
BORDER  = "#44475a"
FG      = "#f8f8f2"   # texto
MUTED   = "#6272a4"   # texto secundario
CYAN    = "#8be9fd"
GREEN   = "#50fa7b"
PURPLE  = "#bd93f9"
PINK    = "#ff79c6"
ORANGE  = "#ffb86c"

# colores por "estilo" de boton: normal / acento / verde
BUTTON_COLORS = {
    "TButton":        dict(bg=PANEL,  fg=FG,      hover="#52556b", press="#5d6079"),
    "Accent.TButton": dict(bg=PURPLE, fg=BG_DARK, hover=PINK,      press=CYAN),
    "Go.TButton":     dict(bg=GREEN,  fg=BG_DARK, hover=CYAN,      press="#8be9fd"),
}
DIS_BG, DIS_FG = BG_DARK, MUTED

FONT      = ("Segoe UI", 9, "bold")        # texto del boton
ICON_FONT = ("Segoe UI Symbol", 12)        # iconos (mas grandes que el texto)

# iconos por boton (prefix)
PREFIXES = {
    "Ensamblar y cargar": "\u2699",    # engranaje
    "Step":               "\u25b6|",   # play + barra = step
    "Run":                "\u25b6",    # play
    "Pause":              "\u23f8",    # pausa
    "Reset CPU":          "\u21ba",    # reset
    "Actualizar":         "\u21bb",    # refresh
}
CONNECT_PREFIX = "\u23fb"              # encendido


class RoundedButton(tk.Canvas):
    """Boton plano con esquinas redondeadas, negrita, icono y estado off.

    Imita la API de ttk.Button que usa gui.py: .config(text=.../state=.../
    style=.../command=.../prefix=...) y .pack(). El icono (prefix) persiste
    aunque cambie el texto, util para Conectar/Desconectar. El icono se dibuja
    con una fuente mas grande que el texto.
    """

    def __init__(self, parent, text="", command=None, state="normal",
                 width=None, style="TButton", radius=8, padx=13, pady=6,
                 prefix="", fill=BG, **kw):
        self._text = text
        self._prefix = prefix
        self._minw = width or 0
        self._command = command
        self._state = "disabled" if str(state) == "disabled" else "normal"
        self._style = style
        self._radius = radius
        self._padx = padx
        self._pady = pady
        self._hover = False
        self._pressed = False
        self._ready = False

        self._font = tkfont.Font(font=FONT)
        self._ifont = tkfont.Font(font=ICON_FONT)
        self._gap = 4                       # separacion icono-texto
        self._bw = self._calc_w()
        self._bh = self._calc_h()

        super().__init__(parent, width=self._bw, height=self._bh,
                         highlightthickness=0, bd=0, bg=fill, **kw)
        self._ready = True
        self._draw()

        self.bind("<Enter>", self._on_enter)
        self.bind("<Leave>", self._on_leave)
        self.bind("<Button-1>", self._on_press)
        self.bind("<ButtonRelease-1>", self._on_release)

    # ---------------------------------------------------------------- helpers
    def _icon_w(self):
        return self._ifont.measure(self._prefix) if self._prefix else 0

    def _text_w(self):
        return self._font.measure(self._text) if self._text else 0

    def _calc_w(self):
        w = self._icon_w() + self._text_w()
        if self._prefix and self._text:
            w += self._gap
        return int(max(w + 2 * self._padx, self._minw * 9, 26))

    def _calc_h(self):
        return int(max(self._font.metrics("linespace"),
                       self._ifont.metrics("linespace")) + 2 * self._pady)

    def _apply_size(self):
        self._bw = self._calc_w()
        self._bh = self._calc_h()
        super().configure(width=self._bw, height=self._bh)

    # ---------------------------------------------------------------- dibujo
    def _colors(self):
        c = BUTTON_COLORS.get(self._style, BUTTON_COLORS["TButton"])
        if self._state == "disabled":
            return DIS_BG, DIS_FG
        if self._pressed:
            return c["press"], c["fg"]
        if self._hover:
            return c["hover"], c["fg"]
        return c["bg"], c["fg"]

    def _draw(self):
        self.delete("all")
        bgc, fgc = self._colors()
        r = self._radius
        x1, y1, x2, y2 = 1, 1, self._bw - 1, self._bh - 1
        pts = [x1 + r, y1, x2 - r, y1, x2, y1, x2, y1 + r,
               x2, y2 - r, x2, y2, x2 - r, y2, x1 + r, y2,
               x1, y2, x1, y2 - r, x1, y1 + r, x1, y1]
        self.create_polygon(pts, smooth=True, fill=bgc, outline="")

        iw, tw = self._icon_w(), self._text_w()
        gap = self._gap if (self._prefix and self._text) else 0
        total = iw + gap + tw
        x = (self._bw - total) / 2.0
        cy = self._bh / 2.0
        if self._prefix:
            self.create_text(x, cy, text=self._prefix, fill=fgc,
                             font=ICON_FONT, anchor="w")
            x += iw + gap
        if self._text:
            self.create_text(x, cy, text=self._text, fill=fgc,
                             font=FONT, anchor="w")

    # --------------------------------------------------------------- eventos
    def _on_enter(self, _):
        if self._state != "disabled":
            self._hover = True
            self.configure(cursor="hand2")
            self._draw()

    def _on_leave(self, _):
        self._hover = False
        self._pressed = False
        self.configure(cursor="")
        self._draw()

    def _on_press(self, _):
        if self._state != "disabled":
            self._pressed = True
            self._draw()

    def _on_release(self, _):
        if self._state != "disabled":
            was = self._pressed
            self._pressed = False
            self._draw()
            if was and self._command:
                self._command()

    # ------------------------------------------------------- API ttk.Button
    def config(self, **kw):
        self.configure(**kw)

    def configure(self, **kw):
        if not self._ready:
            return super().configure(**kw)

        redraw = False
        for key in ("text", "prefix"):
            if key in kw:
                setattr(self, "_" + key, kw.pop(key))
                redraw = True
        if "state" in kw:
            self._state = "disabled" if str(kw.pop("state")) == "disabled" else "normal"
            self._hover = self._pressed = False
            redraw = True
        if "command" in kw:
            self._command = kw.pop("command")
        if "style" in kw:
            self._style = kw.pop("style")
            redraw = True
        if kw:
            super().configure(**kw)
        if redraw:
            self._apply_size()
            self._draw()


# ------------------------------------------------------------- solapas (tabs)
_TAB_IMGS = []          # hay que mantener referencia a los PhotoImage


def _tab_image(bg, outline, radius=6, w=26, h=26, top=0):
    """Solapa con esquinas SUPERIORES redondeadas y base recta.

    Se dibuja un rectangulo redondeado mas alto que la imagen y se recorta la
    parte de abajo (base recta). El parametro `top` baja el borde superior:
    asi las solapas NO seleccionadas quedan mas bajitas y la seleccionada,
    que usa top=0, se ve mas alta.
    """
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(img).rounded_rectangle(
        [0, top, w - 1, h - 1 + radius], radius=radius,
        fill=bg, outline=outline, width=1)
    return ImageTk.PhotoImage(img)


def _style_rounded_tabs(style):
    """Da forma de 'pastilla' a las solapas y elimina el borde blanco de clam."""
    # 1) el borde blanco sale del lightcolor/darkcolor por defecto de clam
    style.configure("TNotebook", background=BG, borderwidth=0, relief="flat",
                    lightcolor=BG, darkcolor=BG, bordercolor=BG,
                    tabmargins=(2, 6, 2, 0))

    if not _HAS_PIL:
        style.configure("TNotebook.Tab", background=BG_DARK, foreground=MUTED,
                        padding=(16, 8), borderwidth=0, relief="flat",
                        lightcolor=BG_DARK, darkcolor=BG_DARK, bordercolor=BG_DARK)
        style.map("TNotebook.Tab",
                  background=[("selected", PANEL), ("active", PANEL)],
                  foreground=[("selected", CYAN), ("active", FG)],
                  lightcolor=[("selected", PANEL), ("active", PANEL)],
                  darkcolor=[("selected", PANEL), ("active", PANEL)],
                  bordercolor=[("selected", CYAN), ("active", MUTED)])
        return

    normal   = _tab_image(BG_DARK, BG_DARK, top=5)   # reposo: mas bajita
    active   = _tab_image(PANEL, PANEL, top=5)       # hover: mas bajita
    selected = _tab_image(BG, CYAN, top=0)           # seleccionada: mas alta
    _TAB_IMGS.extend([normal, active, selected])

    try:
        style.element_create("Rounded.Tab", "image", normal,
                             ("active", active), ("selected", selected),
                             border=10, sticky="nswe")
        style.layout("TNotebook.Tab", [
            ("Rounded.Tab", {"sticky": "nswe", "children": [
                ("Notebook.padding", {"sticky": "nswe", "children": [
                    ("Notebook.label", {"sticky": "nswe"})]})]})])
    except tk.TclError:
        pass

    style.configure("TNotebook.Tab", padding=(14, 2), foreground=MUTED,
                    background=BG, bordercolor=BG, lightcolor=BG, darkcolor=BG)
    style.map("TNotebook.Tab",
              foreground=[("selected", CYAN), ("active", FG)])


# ----------------------------------------------------------------- estilo ttk
def apply_dark_theme(root):
    """Configura ttk (menos los botones) con la paleta oscura."""
    # El fondo de la ventana raiz NO lo cambia ttk: con el tema claro, los
    # margenes/padding entre paneles se veian gris claro (#f0f0f0).
    root.configure(bg=BG)

    style = ttk.Style(root)
    try:
        style.theme_use("clam")
    except tk.TclError:
        pass

    style.configure(".",
        background=BG, foreground=FG, fieldbackground=BG_DARK,
        bordercolor=BORDER, lightcolor=BG, darkcolor=BG_DARK,
        troughcolor=BG_DARK, focuscolor=CYAN, font=("Segoe UI", 9))

    style.configure("TFrame", background=BG)
    style.configure("TLabel", background=BG, foreground=FG)

    style.configure("TEntry",
        fieldbackground=BG_DARK, foreground=FG, insertcolor=CYAN,
        bordercolor=BORDER, lightcolor=BORDER, darkcolor=BORDER, padding=3)
    style.map("TEntry",
        fieldbackground=[("disabled", BG_DARK)], foreground=[("disabled", MUTED)])

    style.configure("TCombobox",
        fieldbackground=BG_DARK, background=PANEL, foreground=FG,
        arrowcolor=CYAN, bordercolor=BORDER, lightcolor=BORDER,
        darkcolor=BORDER, padding=3)
    style.map("TCombobox",
        fieldbackground=[("readonly", BG_DARK), ("disabled", BG_DARK)],
        foreground=[("disabled", MUTED)], background=[("active", MUTED)])

    root.option_add("*TCombobox*Listbox.background", BG_DARK)
    root.option_add("*TCombobox*Listbox.foreground", FG)
    root.option_add("*TCombobox*Listbox.selectBackground", PURPLE)
    root.option_add("*TCombobox*Listbox.selectForeground", BG_DARK)

    _style_rounded_tabs(style)

    style.configure("TPanedwindow", background=BG)
    style.configure("Sash", background=BORDER, gripcount=0)

    style.configure("Treeview",
        background=BG, fieldbackground=BG, foreground=FG,
        bordercolor=BORDER, borderwidth=0, rowheight=21)
    style.map("Treeview",
        background=[("selected", PANEL)], foreground=[("selected", CYAN)])
    style.configure("Treeview.Heading",
        background=PANEL, foreground=CYAN, relief="flat", padding=(4, 5),
        font=("Segoe UI", 9, "bold"))
    style.map("Treeview.Heading", background=[("active", MUTED)])


# ------------------------------------------------------- barra de titulo (DWM)
# Colores de la barra de titulo de la ventana (donde dice el nombre).
# Cambiar aca para probar otros colores.
TITLEBAR_BG  = BG_DARK     # fondo de la barra
TITLEBAR_FG  = FG          # texto del titulo
TITLEBAR_BRD = PANEL       # borde de la ventana


def _titlebar_dark(root, caption=TITLEBAR_BG, text=TITLEBAR_FG, border=TITLEBAR_BRD):
    """Pinta la barra de titulo y el borde de la ventana (solo Windows).

    Usa la API DWM:
      - modo oscuro        : DWMWA_USE_IMMERSIVE_DARK_MODE (20; 19 en builds viejas)
      - color de la barra  : DWMWA_CAPTION_COLOR            (35)  [Win11 22000+]
      - color del texto    : DWMWA_TEXT_COLOR               (36)
      - color del borde    : DWMWA_BORDER_COLOR             (34)
    Devuelve [(clave, resultado)] para poder depurar.
    """
    res = []
    if not sys.platform.startswith("win"):
        return res
    try:
        import ctypes
        from ctypes import wintypes

        def colorref(hx):                      # "#rrggbb" -> 0x00BBGGRR
            hx = hx.lstrip("#")
            r, g, b = int(hx[0:2], 16), int(hx[2:4], 16), int(hx[4:6], 16)
            return r | (g << 8) | (b << 16)

        hwnd = ctypes.windll.user32.GetParent(root.winfo_id()) or root.winfo_id()
        dwm = ctypes.windll.dwmapi

        dark = ctypes.c_int(1)
        for attr in (20, 19):
            hr = dwm.DwmSetWindowAttribute(wintypes.HWND(hwnd), attr,
                                           ctypes.byref(dark), ctypes.sizeof(dark))
            res.append(("dark_%d" % attr, hr))
        for attr, hx in ((35, caption), (36, text), (34, border)):
            c = ctypes.c_int(colorref(hx))
            hr = dwm.DwmSetWindowAttribute(wintypes.HWND(hwnd), attr,
                                           ctypes.byref(c), ctypes.sizeof(c))
            res.append(("%d=%s" % (attr, hx), hr))
    except Exception as e:
        res.append(("error", repr(e)))
    return res


# ----------------------------------------------------------------------- App
class App:
    def __init__(self, root):
        self.root = root
        root.title("RISC-V debug")
        self.ser = None
        self.link = None
        self.running = False
        self.prev_regs = [0] * 32
        self._build()
        # tema oscuro: se aplica despues de crear los widgets (los re-estiliza)
        apply_dark_theme(root)
        self._recolor()
        # barra de titulo oscura (Windows); reintento por si todavia no existe
        # el handle definitivo de la ventana.
        _titlebar_dark(root)
        root.after(300, lambda: _titlebar_dark(root))

    # ------------------------------------------------------------------ UI
    def _build(self):
        top = ttk.Frame(self.root, padding=4)
        top.pack(fill="x")
        ttk.Label(top, text="Puerto").pack(side="left")
        self.port = ttk.Combobox(top, width=38, values=self._ports())
        self.port.pack(side="left", padx=4)
        RoundedButton(top, text="↻", width=3, command=lambda: self.port.config(values=self._ports())).pack(side="left")
        ttk.Label(top, text="Baud").pack(side="left", padx=(8, 0))
        self.baud = ttk.Entry(top, width=7)
        self.baud.insert(0, "19200")
        self.baud.pack(side="left", padx=4)
        self.btn_conn = RoundedButton(top, text="Conectar", command=self.toggle_connect)
        self.btn_conn.pack(side="left", padx=4)

        bar = ttk.Frame(self.root, padding=(4, 0))
        bar.pack(fill="x")
        self.buttons = {}
        for name, cmd in (("Ensamblar y cargar", self.assemble_and_load), ("Step", self.step),
                          ("Run", self.run), ("Pause", self.pause), ("Reset CPU", self.reset),
                          ("Actualizar", self.refresh)):
            b = RoundedButton(bar, text=name, command=cmd, state="disabled")
            b.pack(side="left", padx=2, pady=4)
            self.buttons[name] = b
        RoundedButton(bar, text="Abrir…", command=self.open_file).pack(side="right", padx=2)
        RoundedButton(bar, text="Guardar…", command=self.save_file).pack(side="right", padx=2)

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

    def _recolor(self):
        """Colorea los widgets que no son ttk (Text) y agrega los iconos."""
        for w in (self.editor, self.hexview, self.stages, self.dmemview):
            w.configure(bg=BG_DARK, fg=FG, insertbackground=CYAN,
                        selectbackground=PANEL, selectforeground=FG,
                        highlightthickness=0, borderwidth=0)

        self.regtree.tag_configure("changed", background=ORANGE, foreground=BG_DARK)

        # iconos
        for name, pfx in PREFIXES.items():
            if name in self.buttons:
                self.buttons[name].configure(prefix=pfx)
        self.btn_conn.configure(prefix=CONNECT_PREFIX)

        # jerarquia de color
        for name in ("Ensamblar y cargar", "Run"):
            if name in self.buttons:
                self.buttons[name].configure(style="Accent.TButton")
        self.btn_conn.configure(style="Go.TButton")

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
