#!/usr/bin/env python3
"""
debug_host.py - CLI de la debug unit: carga del programa por UART y control del CPU.

Uso:
    python3 debug_host.py --port /dev/ttyUSB1 load prog.hex step 3 dump
    python3 debug_host.py --port /dev/ttyUSB1 asm prog.s run wait dump

Acciones (se ejecutan en orden, en una sola conexion):
    asm <archivo.s>  ensambla (binutils RISC-V) y carga
    load <archivo>   carga .bin crudo o texto con una palabra hex de 32 bits por linea
    step [n]         avanza n ciclos (default 1)
    run              ejecucion continua
    wait [seg]       espera el aviso de halt hasta seg segundos (default 5)
    pause            detiene la ejecucion continua
    reset            reset del CPU (PC = 0, registros en 0); el programa se conserva
    dump             lee el bus de debug: etapas del pipeline, registros y dmem

Despues de run, usar wait o pause antes de dump. Requiere pyserial.
"""
import argparse
import sys

from debug_protocol import DebugLink, ProtocolError, format_dump, read_program


def run_actions(link, actions):
    i = 0
    while i < len(actions):
        action = actions[i].lower()
        i += 1
        if action in ("load", "asm"):
            if i >= len(actions):
                raise SystemExit(f"{action}: falta el archivo")
            path = actions[i]
            i += 1
            if action == "asm":
                from assemble import assemble_file
                words = assemble_file(path).words
            else:
                words = read_program(path)
            link.load(words)
            print(f"load: {len(words)} instrucciones")
        elif action == "step":
            n = 1
            if i < len(actions) and actions[i].isdigit():
                n = int(actions[i])
                i += 1
            for k in range(n):
                if not link.step():
                    print(f"halt: se ejecutaron {k} de {n} pasos")
                    break
        elif action == "run":
            if not link.run():
                print("el CPU esta en halt: no arranca (usar reset o load)")
        elif action == "wait":
            seconds = 5.0
            if i < len(actions) and actions[i].replace(".", "", 1).isdigit():
                seconds = float(actions[i])
                i += 1
            print("halt" if link.poll_halt(seconds) else f"sin halt despues de {seconds} s")
        elif action == "pause":
            if link.pause():
                print("halt")
        elif action == "reset":
            link.reset()
        elif action == "dump":
            print(format_dump(link.dump()))
        else:
            raise SystemExit(f"accion desconocida: {action}")


def main(argv=None):
    ap = argparse.ArgumentParser(description="Host de la debug unit del RISC-V", epilog=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", required=True, help="puerto serie (ej. /dev/ttyUSB1 o COM4)")
    ap.add_argument("--baud", type=int, default=19200, help="baud rate (default 19200)")
    ap.add_argument("actions", nargs="+", help="acciones a ejecutar en orden")
    args = ap.parse_args(argv)

    import serial

    with serial.Serial(args.port, args.baud, bytesize=8, parity="N", stopbits=1, timeout=1) as ser:
        ser.reset_input_buffer()
        try:
            run_actions(DebugLink(ser), args.actions)
        except (ProtocolError, ValueError) as e:
            sys.exit(f"error: {e}")


if __name__ == "__main__":
    main()
