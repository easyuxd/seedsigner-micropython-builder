# Native build (no Docker) and the easyuxd Redesign

easyuxd fork additions. Upstream's Docker flow (`make docker-build-all` + `make dist`) is unchanged.

## One firmware, two UIs

Every image built from this fork contains both:

| UI | What boots | Orientation |
|---|---|---|
| **Classic** (default) | the SeedSigner app | landscape |
| **Redesign** | the easyuxd clickable prototype from [easyuxd/seedsigner-lvgl-screens](https://github.com/easyuxd/seedsigner-lvgl-screens) (`components/seedsigner/redesign/`, with `tokens.json` + `prototype.json` compiled in) | portrait |

The choice is one NVS value (namespace `seedsigner`, key `ui`: 0 = Classic, 1 = Redesign). `display_manager` reads it at power-on, because orientation is fixed at `board_init()`, and the launcher (`/main.py`, from `tools/_launcher.py`) reads it to decide what to run. Switch with no reflash:

```bash
python3 tools/set_ui.py redesign     # or: classic, status
```

It finds the board on USB by itself and restarts it. It needs pyserial, which the esptool virtual environment already has (`source ~/esptool-venv/bin/activate`).

## Build natively

One-time setup:

1. ESP-IDF at the version the Docker image pins (`ARG ESP_IDF_REF` in `Dockerfile`, currently v5.5.5), in its **own** folder so other projects' ESP-IDF stays untouched:
   ```bash
   git clone -b v5.5.5 --depth 1 --recursive --shallow-submodules https://github.com/espressif/esp-idf.git ~/esp/esp-idf-v5.5.5
   IDF_TOOLS_PATH=~/.espressif ~/esp/esp-idf-v5.5.5/install.sh esp32p4
   ```
2. Nothing else: `native_build.sh` fetches the submodules it needs on first run (MicroPython, the screens, the app, embit, cUR, secp256k1 and board_common with its camera pipeline).

Build (output in `dist/<BOARD>[-<VARIANT>]/`, ready for `esptool … write-flash @flash_args`):

```bash
scripts/native_build.sh                                                   # Waveshare 4.3" (chip v3.x)
BOARD=WAVESHARE_ESP32_P4_WIFI6_TOUCH_LCD_35 BOARD_VARIANT=PRE_REV3 scripts/native_build.sh   # 3.5", chip v1.x
```

`native_build.sh` runs the same steps as the Docker flow, against the local ESP-IDF, and checks the ESP-IDF version matches the pin. Two differences matter:

- **The MicroPython patches are applied without a commit** (`MP_PATCH_NO_COMMIT=1`), and the submodule is restored to its pinned commit when the build exits. The Docker flow's throwaway commit uses a fixed `builder@localhost` identity, which machines that enforce a committer identity per folder rightly refuse.
- It never touches global git config. (The Docker flow sets `safe.directory` inside its container.)

A first build compiles everything; later builds are incremental.
