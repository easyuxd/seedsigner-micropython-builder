#!/usr/bin/env python3
"""Choose which UI a flashed board boots: Classic (the SeedSigner app, landscape) or
the easyuxd Redesign prototype (portrait). No reflash: the choice is one NVS value
(namespace "seedsigner", key "ui": 0 = Classic, 1 = Redesign) that the firmware reads
at power-on (display_manager init) and the launcher reads in /main.py.

    python3 tools/set_ui.py redesign          # switch to the Redesign, then reboot
    python3 tools/set_ui.py classic           # switch back
    python3 tools/set_ui.py status            # print the current choice
    python3 tools/set_ui.py redesign --port /dev/cu.usbmodem1101

The port is found automatically (the boards' USB-serial chip, 1a86:55d3) unless given.
Needs pyserial, which esptool already installs (run it from the esptool venv).
"""
import argparse
import sys

import serial  # pyserial
from serial.tools import list_ports

from mpy_repl import exec_code

UI_VALUES = {"classic": 0, "redesign": 1}
BOARD_USB_ID = (0x1A86, 0x55D3)  # WCH CH343 on the Waveshare P4 boards


def find_port():
    ports = [p.device for p in list_ports.comports() if (p.vid, p.pid) == BOARD_USB_ID]
    # macOS lists both /dev/cu.* and /dev/tty.*; cu is the one to open.
    ports.sort(key=lambda d: (not d.startswith("/dev/cu."), d))
    if not ports:
        sys.exit("No board found on USB. Plug it in with a data cable (or pass --port).")
    return ports[0]


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("ui", choices=["classic", "redesign", "status"])
    ap.add_argument("--port", help="serial port (default: auto-detect)")
    args = ap.parse_args()

    port = args.port or find_port()
    with serial.Serial(port, 115200, timeout=0.1) as ser:
        if args.ui == "status":
            out = exec_code(ser, (
                "import esp32\n"
                "try:\n v = esp32.NVS('seedsigner').get_i32('ui')\n"
                "except OSError:\n v = 0\n"
                "print('redesign' if v == 1 else 'classic')\n"), timeout=10)
            print(f"{port}: {out}")
            return
        out = exec_code(ser, (
            "import esp32\n"
            "n = esp32.NVS('seedsigner')\n"
            f"n.set_i32('ui', {UI_VALUES[args.ui]})\n"
            "n.commit()\n"
            "print('saved')\n"), timeout=10)
        if "saved" not in out:
            sys.exit(f"Could not save the setting:\n{out}")
        # Hard reset so display init re-reads the choice (orientation is fixed at boot).
        ser.write(b"import machine; machine.reset()\r")
    print(f"{port}: set to {args.ui}; the board is restarting.")


if __name__ == "__main__":
    main()
