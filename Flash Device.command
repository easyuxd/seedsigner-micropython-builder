#!/bin/bash
# Double-click to flash the plugged-in board with the easyuxd firmware (docs/native-build.md).
#
# 1. finds the board on its UART USB-C port
# 2. reads the chip revision and flash size, and picks the image:
#      chip v1.x -> PRE_REV3 variant; 16 MB flash -> 3.5", 32 MB -> 4.3"
# 3. builds that image if it isn't built yet (or if you ask for a fresh build)
# 4. asks before flashing, then flashes
# 5. asks which UI to boot (Classic or Redesign) and sets it with tools/set_ui.py
set -euo pipefail
cd "$(dirname "$0")"

VENV="$HOME/esptool-venv"
UART_ID="1A86:55D3"   # the port labelled UART (USB-serial chip)
NATIVE_ID="303A:4001" # the P4's own USB port: esptool can't flash through it

say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
die()  { printf '\n\033[31m%s\033[0m\n\nPress Return to close.' "$*"; read -r _; exit 1; }
ask()  { local a; read -r -p "$1 " a; [[ "$a" =~ ^[Yy] ]]; }

[ -x "$VENV/bin/esptool" ] || die "esptool isn't installed. Once, in Terminal:
  python3 -m venv ~/esptool-venv && ~/esptool-venv/bin/pip install --upgrade esptool"
# shellcheck disable=SC1091
source "$VENV/bin/activate"

# 1. Find the board.
ports="$(python3 -m serial.tools.list_ports -v 2>/dev/null)"
port="$(printf '%s\n' "$ports" | grep -B2 "VID:PID=$UART_ID" | grep -o '^/dev/cu\.[^ ]*' | head -1 || true)"
if [ -z "$port" ]; then
  if printf '%s\n' "$ports" | grep -q "VID:PID=$NATIVE_ID"; then
    die "The board is plugged into its other USB-C port. Move the cable to the port labelled UART."
  fi
  die "No board found. Plug it in with a data cable (a charge-only cable shows no port)."
fi

# 2. Identify it.
say "Checking the board on ${port}…"
info="$(esptool -p "$port" flash-id 2>&1)" || die "Couldn't talk to the board:
$info

Unplug and replug it, close any other serial tool, and try again."
rev="$(printf '%s\n' "$info" | sed -n 's/.*(revision v\([0-9.]*\)).*/\1/p' | head -1)"
flash="$(printf '%s\n' "$info" | sed -n 's/^Detected flash size: //p' | head -1)"
case "$flash" in
  16MB) board=WAVESHARE_ESP32_P4_WIFI6_TOUCH_LCD_35; name='3.5″' ;;
  32MB) board=WAVESHARE_ESP32_P4_WIFI6_TOUCH_LCD_43; name='4.3″' ;;
  *) die "Unknown board (flash size '${flash:-?}'). Only the Waveshare 3.5″ and 4.3″ are set up." ;;
esac
[ -n "$rev" ] || die "Couldn't read the chip revision:
$info"
variant=""; [ "${rev%%.*}" -lt 3 ] && variant=PRE_REV3
image="dist/$board${variant:+-$variant}"
echo "Found: Waveshare $name, chip v$rev, $flash flash -> image ${image#dist/}"

# 3. Build if needed.
if [ ! -f "$image/micropython.bin" ]; then
  say "This image isn't built yet. Building it (first build ~10 min)…"
  BOARD="$board" BOARD_VARIANT="$variant" scripts/native_build.sh || die "The build failed (see above)."
else
  built="$(date -r "$image/micropython.bin" '+%b %-d, %H:%M')"
  if ask "The image was built $built. Build a fresh one first? [y/N]"; then
    BOARD="$board" BOARD_VARIANT="$variant" scripts/native_build.sh || die "The build failed (see above)."
  fi
fi

# 4. Flash, with the owner's OK.
say "Ready to flash the $name on $port. This replaces the firmware on the board (about 4 min)."
ask "Flash it now? [y/N]" || die "Nothing was flashed."
(cd "$image" && esptool --chip esp32p4 -p "$port" write-flash @flash_args) || die "Flashing failed (see above)."

# 5. Pick the UI. The choice lives in NVS, which flashing leaves alone.
say "Which UI should it boot?"
echo "  1) Redesign (portrait prototype)"
echo "  2) Classic (the SeedSigner app)"
echo "  3) Keep what it had"
read -r -p "Choose [1]: " pick
case "${pick:-1}" in
  1) ui=redesign ;; 2) ui=classic ;; *) ui="" ;;
esac
if [ -n "$ui" ]; then
  echo "Waiting for the board to start…"
  for _ in 1 2 3 4 5 6; do
    sleep 5
    python3 tools/set_ui.py "$ui" --port "$port" 2>/dev/null && { ok=1; break; }
  done
  [ -n "${ok:-}" ] || die "Flashed, but couldn't set the UI. Later, in Terminal:
  source ~/esptool-venv/bin/activate && python3 tools/set_ui.py $ui"
fi

say "Done. The $name is restarting${ui:+ into $ui}."
printf 'Press Return to close.'; read -r _
