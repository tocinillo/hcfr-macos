# Changes

Each version has its DMG in [Releases](https://github.com/salondigital/hcfr-macos/releases).

## 1.3.1

First version of this fork, on top of Jorge Velázquez's HCFR Colorimeter for macOS 1.3.

- **madVR Envy / madTPG** as pattern generator (madVR's network protocol).
- **PGenerator output from HCFR**: SDR or HDR10 with its metadata, color format (RGB / YCbCr 4:4:4 /
  4:2:2), 8 or 10 bits, limited or full range, colorimetry. Automatic mode: HDR10 (10 bits) when the
  reference curve is ST.2084, SDR otherwise. 10-bit patches in HDR10.
- Merged Jorge's 1.2 and 1.3: movable measurement window, floating message panel, connect the meter
  when it is chosen, i1Pro calibration fix, "return the meter to the screen" after calibrating.
- Calibration wizard (⌘⇧W) for SDR and HDR10 (HLG removed from the wizard).
- Interface in English and Spanish; all of HCFR's measures, views, graphs and preferences.
- Export HCFR's CSV sheets (choose which), `hcfr://` automation for the PGC JVC autocalibration.
- Raspberry Pi address in Preferences, any patch size, faster PGenerator+ answers.
- Help menu: colorimeter installation, check for updates, support.
- DMG installer.
