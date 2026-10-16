#!/usr/bin/env bash
# Build flashable firmware natively (macOS or Linux), without Docker.
#
# The same steps as `make docker-build-all` + `make dist`, against a local ESP-IDF
# pinned to the version the Docker image bakes (Dockerfile ESP_IDF_REF). Uses the
# deps/seedsigner + deps/embit submodules for the frozen app, like CI.
#
#   scripts/native_build.sh                                   # Waveshare 4.3" (v3.x chip)
#   BOARD=WAVESHARE_ESP32_P4_WIFI6_TOUCH_LCD_35 BOARD_VARIANT=PRE_REV3 scripts/native_build.sh
#
# One-time setup (see docs/native-build.md): ESP-IDF at $IDF_DIR (default
# ~/esp/esp-idf-v<pin>) with its esp32p4 tools in $IDF_TOOLS_PATH (default ~/.espressif),
# The submodules are fetched here as needed. Output: dist/<BOARD>[-<VARIANT>]/.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

IDF_PIN="$(sed -n 's/^ARG ESP_IDF_REF=//p' Dockerfile)"
export BOARD="${BOARD:-WAVESHARE_ESP32_P4_WIFI6_TOUCH_LCD_43}"
export BOARD_VARIANT="${BOARD_VARIANT:-}"
export IDF_DIR="${IDF_DIR:-$HOME/esp/esp-idf-$IDF_PIN}"
export IDF_TOOLS_PATH="${IDF_TOOLS_PATH:-$HOME/.espressif}"
export SS_APP_DIR="${SS_APP_DIR:-$ROOT_DIR/deps/seedsigner}"
export SS_EMBIT_DIR="${SS_EMBIT_DIR:-$ROOT_DIR/deps/embit}"
# Apply the MicroPython patches without a commit (see apply_micropython_mods.sh).
export MP_PATCH_NO_COMMIT=1

if [ ! -f "$IDF_DIR/export.sh" ]; then
  echo "ESP-IDF $IDF_PIN not found at $IDF_DIR. Install it once with:"
  echo "  git clone -b $IDF_PIN --depth 1 --recursive --shallow-submodules https://github.com/espressif/esp-idf.git $IDF_DIR"
  echo "  IDF_TOOLS_PATH=$IDF_TOOLS_PATH $IDF_DIR/install.sh esp32p4"
  exit 1
fi
have="$(git -C "$IDF_DIR" describe --tags 2>/dev/null || echo unknown)"
if [ "$have" != "$IDF_PIN" ]; then
  echo "ESP-IDF at $IDF_DIR is $have; this builder pins $IDF_PIN (Dockerfile ESP_IDF_REF)."
  exit 1
fi

# Same clean-tree guard + restore as docker_build_all.sh (the build patches MicroPython).
MP_DIR="$ROOT_DIR/deps/micropython/upstream"
if [ -n "$(git -C "$MP_DIR" status --porcelain --ignore-submodules 2>/dev/null)" ] && \
   [ "${MP_ALLOW_DIRTY:-}" != "1" ]; then
  echo "ERROR: MicroPython submodule has uncommitted changes. Restore it with"
  echo "  scripts/restore_micropython_clean.sh   (or rerun with MP_ALLOW_DIRTY=1)"
  exit 1
fi
trap './scripts/restore_micropython_clean.sh "$ROOT_DIR/deps" >/dev/null 2>&1 || true' EXIT
# Start from a fresh-clone state: the ESP-IDF component manager re-fetches components
# (overwriting the builder's LVGL/tinyusb patches) when gitignored managed_components/
# from an earlier run meet the dependencies.lock that the restore above deletes.
rm -rf "$MP_DIR/ports/esp32/managed_components"

# Fetch the submodules a firmware build needs, only where missing: a checked-out
# submodule is never moved, so local work in one (say, the screens) is what gets built.
for sm in deps/micropython/upstream deps/cUR deps/esp-secp256k1 deps/seedsigner deps/embit \
          deps/seedsigner-lvgl-screens ports/esp32/board_common; do
  [ -e "$sm/.git" ] || git submodule update --init --depth 50 "$sm"
done
[ -e deps/esp-secp256k1/secp256k1-zkp/.git ] || git -C deps/esp-secp256k1 submodule update --init --depth 1
[ -e deps/seedsigner-lvgl-screens/third_party/lvgl/.git ] || \
  git -C deps/seedsigner-lvgl-screens submodule update --init --depth 1
[ -e ports/esp32/board_common/components/esp-camera-pipeline/.git ] || \
  git -C ports/esp32/board_common submodule update --init --recursive --depth 1

python3 tools/stage_frozen_app.py --board "$BOARD"
./scripts/prepare_sources_from_image.sh "$ROOT_DIR/deps"
./scripts/apply_idf_mods.sh "$ROOT_DIR/deps"
./scripts/apply_micropython_mods.sh "$ROOT_DIR/deps"
./scripts/build_firmware.sh "$ROOT_DIR/deps"
make dist BOARD="$BOARD" ${BOARD_VARIANT:+BOARD_VARIANT="$BOARD_VARIANT"}
