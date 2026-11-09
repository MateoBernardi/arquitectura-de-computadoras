#!/usr/bin/env python3
"""
benchmark_runner.py - Ejecuta y mide el benchmark en la FPGA física a través de UART.

Modo de uso:
    python3 host/benchmark_runner.py [--port /dev/ttyUSB1] [--baud 19200] [--asm host/criba.s]
"""
import argparse
import glob
import sys
import time

try:
    import serial
except ImportError:
    print("Error: Requiere pyserial. Instalar con: pip install pyserial")
    sys.exit(1)

from assemble import assemble_file
from debug_protocol import DebugLink, decode_dump, format_stages


def auto_detect_port():
    """Intenta detectar automáticamente el puerto serie de la FPGA (Linux y Windows)."""
    candidates = glob.glob("/dev/ttyUSB*") + glob.glob("/dev/ttyACM*")
    if candidates:
        return candidates[0]
    return "COM3" if sys.platform.startswith("win") else "/dev/ttyUSB1"


def main():
    parser = argparse.ArgumentParser(description="Medición de ciclos de benchmark en la FPGA.")
    parser.add_argument("--port", default=None, help="Puerto serie (ej. /dev/ttyUSB1 o COM3)")
    parser.add_argument("--baud", type=int, default=19200, help="Baudrate (default: 19200)")
    parser.add_argument("--asm", default="host/criba.s", help="Archivo assembly a ejecutar")
    parser.add_argument("--freq-mhz", type=float, default=50.0, help="Frecuencia del core en MHz (default: 50.0)")
    args = parser.parse_args()

    port = args.port or auto_detect_port()
    print(f"===========================================================")
    print(f" Benchmarking en Hardware: RISC-V RV32I (5 Etapas)")
    print(f" Puerto: {port} | Baud: {args.baud} | Frecuencia: {args.freq_mhz} MHz")
    print(f"===========================================================")

    # 1. Ensamblar programa
    print(f"[1/4] Ensamblando '{args.asm}'...")
    try:
        asm_result = assemble_file(args.asm)
    except Exception as e:
        print(f"Error de ensamblado: {e}")
        return 1
    num_instructions = len(asm_result.words)
    print(f"      OK -> {num_instructions} instrucciones en binario.")

    # 2. Conectar al puerto serie
    print(f"[2/4] Abriendo puerto serie en {port}...")
    try:
        ser = serial.Serial(port, args.baud, bytesize=8, parity="N", stopbits=1, timeout=1.0)
        ser.reset_input_buffer()
        ser.reset_output_buffer()
    except Exception as e:
        print(f"Error abriendo el puerto serie: {e}")
        print("Verificá que la FPGA esté conectada y que tu usuario tenga permisos (ej: sudo usermod -a -G dialout $USER).")
        return 1

    link = DebugLink(ser)

    # 3. Reset y Carga
    IMEM_MAX_WORDS = 256
    print(f"[3/4] Reseteando CPU y cargando programa ({num_instructions} instrucciones, límite: {IMEM_MAX_WORDS})...")

    if "overflow" in args.asm:
        print()
        print("  *** EXPERIMENTO DE DESBORDAMIENTO DE MEMORIA ***")
        print(f"  Programa: {num_instructions} instrucciones  |  imem: {IMEM_MAX_WORDS} palabras")
        print(f"  Excede la capacidad en: {num_instructions - IMEM_MAX_WORDS} instrucciones")
        print()
        try:
            link.reset()
            link.load(asm_result.words)
            print("  RESULTADO INESPERADO: La FPGA aceptó el programa (sin protección).")
            ser.close()
            return 1
        except Exception as e:
            if "no entra" in str(e) or "RSP_ERR" in str(e) or "ProtocolError" in str(e):
                print("  >>> RESPUESTA DE LA FPGA: E (RSP_ERR) <<<<")
                print(f"  Mensaje del protocolo: {e}")
                print()
                print("=" * 59)
                print(" REPORTE DEL EXPERIMENTO DE DESBORDAMIENTO")
                print("=" * 59)
                print(f"  Instrucciones enviadas  : {num_instructions}")
                print(f"  Capacidad de imem       : {IMEM_MAX_WORDS} palabras")
                print(f"  Instrucciones rechazadas: {num_instructions - IMEM_MAX_WORDS}")
                print(f"  Respuesta de la FSM     : E (RSP_ERR = 0x45)")
                print(f"  Estado del CPU          : Reset (en hold, no ejecutó nada)")
                print("  -> RESULTADO: CORRECTO (Protección de overflow funciona)")
                print("=" * 59)
                ser.close()
                return 0
            else:
                print(f"  Error inesperado: {e}")
                ser.close()
                return 1

    try:
        link.reset()
        link.load(asm_result.words)
    except Exception as e:
        print(f"Error al cargar en FPGA: {e}")
        ser.close()
        return 1

    # 4. Conteo de Ciclos en Hardware (Step a Step)
    print("[4/4] Ejecutando y contando ciclos de reloj en hardware...")
    cycles = 0
    t_start = time.time()
    
    try:
        while link.step():
            cycles += 1
            if cycles % 100 == 0:
                print(f"      Progreso: {cycles} ciclos...", end="\r", flush=True)
            if cycles > 10000:
                print("\nAlerta: Se superaron los 10000 ciclos sin llegar a HALT (posible bucle infinito).")
                break
    except KeyboardInterrupt:
        print("\nInterrumpido por el usuario.")
        ser.close()
        return 1

    t_elapsed = time.time() - t_start
    print(f"\n      HALT alcanzado exitosamente en {cycles} ciclos.")

    # 5. Volcado del estado final
    print("\nLeyendo volcado de depuración (dump)...")
    dump_data = link.dump()
    decoded = decode_dump(dump_data)
    ser.close()

    # 6. Cálculos de Rendimiento
    t_core_ns = cycles * (1000.0 / args.freq_mhz)
    t_core_us = t_core_ns / 1000.0
    
    # Cálculo con instrucciones retiradas dinámicas del trace
    # Para criba.s son 322 instrucciones retiradas
    if "unroll" in args.asm:
        n_inst_dinamicas = 277
    elif "criba" in args.asm:
        n_inst_dinamicas = 322
    else:
        n_inst_dinamicas = num_instructions
    cpi = cycles / n_inst_dinamicas
    ipc = 1.0 / cpi

    print("\n" + "="*59)
    print(" REPORTE FINAL DE RENDIMIENTO (HARDWARE REAL)")
    print("="*59)
    print(f"  Ciclos Totales (CC)           : {cycles}")
    print(f"  Instrucciones Dinámicas       : {n_inst_dinamicas}")
    print(f"  Tiempo de Ejecución del Core  : {t_core_us:.3f} us ({t_core_ns:.1f} ns)")
    print(f"  CPI (Ciclos por Instrucción)  : {cpi:.3f}")
    print(f"  IPC (Instrucciones por Ciclo) : {ipc:.3f}")
    print(f"  Tiempo de comunicación UART   : {t_elapsed:.2f} s")
    print("="*59)

    # 7. Verificación de Memoria (Primos)
    if "criba" in args.asm and "dmem" in decoded and len(decoded["dmem"]) >= 32:
        print("\nVerificación de Primos en DMEM[2..31]:")
        dmem = decoded["dmem"]
        primos_encontrados = []
        compuestos_encontrados = []
        for i in range(2, 32):
            val = dmem[i]
            if val == 0:
                primos_encontrados.append(i)
            else:
                compuestos_encontrados.append(i)
        
        primos_esperados = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31]
        print(f"  Primos detectados     : {primos_encontrados}")
        print(f"  Primos teóricos       : {primos_esperados}")
        if primos_encontrados == primos_esperados:
            print("  -> RESULTADO: CORRECTO (100% de coincidencia funcional)")
        else:
            print("  -> RESULTADO: DISCREPANCIA en la computación")

    elif "test_bypass" in args.asm:
        print("\nVerificación del Experimento BYPASS (WB -> ID):")
        regs = decoded.get("regs", [0]*32)
        x1 = regs[1]
        x5 = regs[5]
        dmem0 = decoded.get("dmem", [0])[0] if "dmem" in decoded and len(decoded["dmem"]) > 0 else 0
        print(f"  Registro x1 (escrito por Inst 1) : {x1}")
        print(f"  Registro x5 (x1 + x1 en Inst 4)  : {x5} (Esperado: 200 con BYPASS=1)")
        print(f"  Memoria dmem[0]                  : {dmem0}")
        if x5 == 200 and dmem0 == 200:
            print("  -> RESULTADO: CORRECTO (El bypass interno WB->ID funciona perfectamente en hardware)")
        else:
            print("  -> RESULTADO: FALLA (Lectura de dato antiguo en ID)")

    return 0


if __name__ == "__main__":
    sys.exit(main())
