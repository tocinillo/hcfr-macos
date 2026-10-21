# HCFR Colorimeter for macOS

A native macOS version of **HCFR Colorimeter**, focused on calibrating TVs and monitors (especially
CRT TVs) with a colorimeter and a calibration DVD / external pattern generator.

> **Unofficial port.** This project is not affiliated with or endorsed by the HCFR project. It is
> built from HCFR's open-source code: https://github.com/arthur-liberman/hcfr-code

- Mac version by Jorge Velázquez, Mazatlán, México; this fork (1.3.1) adds the features listed
  in [What's new in this fork](#whats-new-in-this-fork) on top of his 1.3
- Version 1.3.1 — universal app (Apple Silicon and Intel), macOS 14 Sonoma or later
- License: GNU General Public License version 2 (see [LICENSE](LICENSE))

## Features

- **Pattern generator**: patterns come from your DVD / external generator (the app asks for
  each one), from a movable **measurement window**, from a **Raspberry Pi running PGenerator** on
  your network, from a **madVR Envy / madTPG** on your network, or full screen on a display
  connected to the Mac — with PC 0–255 or video 16–235 levels, full field or window patch, and a
  settle time.
- **Measurements**:
  - Grey scale (10–100 IRE, or 0–100 IRE with *Override black* off)
  - Primary colors (Red, Green, Blue + White)
  - Primary and secondary colors (+ Yellow, Cyan, Magenta)
  - Grey scale and colors
- **Start / Stop**: continuous reading of the selected column; click another column to measure it
  without stopping — handy while adjusting a CRT's cut-off/bias and drive/gain.
- HCFR-style tables (x, y, Y, Delta E, delta xy, Y target / delta L), RGB levels, target diagram,
  current measure, the *Gray Scale Balance* chart and a **CIE xy / u'v' diagram** (reference gamut
  and targets, measured colors, gray scale and measured gamut).
- Same color math as HCFR: CIE2000 Delta E ("Absolute Y w/o gamma"), green/yellow/red thresholds,
  power law gamma (2.3 by default), all HCFR color standards (except Custom) and white points
  (D65 by default, D93, D75, D55, D50, DCI, A, B, C, E). Results were checked against HCFR for
  Windows with the same readings.
- Colorimeters supported by HCFR's ArgyllCMS drivers, with the same **Display** corrections
  (built-in and HCFR's CCSS files: CRT, LCD families, OLED, Projector…). Several meters can be
  connected; each is shown with its serial number. Diffuser position is checked like in HCFR.
  Tested with the i1Display family (Calibrite ColorChecker Display, ColorMunki Display); other
  meters supported by the drivers (Spyder, i1Pro, Klein, …) have not been tested yet. On meter
  models not tested yet the diffuser position is not checked, because one user's meter reported
  the diffuser in place when it was not (tested serial prefixes: `C1-`, `CM-`).
  Spectrometers with a high resolution mode (i1Pro, i1Pro2, i1Pro3, ColorMunki) can use 3.3 nm
  instead of the standard 10 nm ("High res" in the Sensor panel).
- Projects (`.hcfrex`), print / PDF report, sounds when a pattern is requested and when a run ends.

## What's new in this fork

Built on Jorge Velázquez's 1.1 and merged with his 1.2 and 1.3:

- **Interface in English and Spanish** (follows the system language, or choose it in Preferences).
- **All of HCFR's measures and views**: near black / near white, saturations, Color Checker
  (GCD, Calman sets, user file), free measures, contrast (ANSI), extended and saturation measure
  menus, data reference (compare with another project), HCFR's graphs (Luminance, Gamma, RGB
  levels, color temperature, CIE diagram — a port of HCFR's own —, spectrum, histograms…).
- **HCFR's preferences**: references (standards, white points, BT.1886, ST.2084 / BT.2390,
  HLG), Delta E formulas, sensor options (reading type, observer, integration time, Hi-Res,
  low light averaging), luxmeter, second meter / simultaneous measures, frame insertion (ABL),
  latency, rounding, chart colors…
- **Calibration wizard** (⌘⇧W), Calman-style: meter → generator → targets → measure → white
  balance and colors with live bars → final measure and before / after summary.
- **madVR Envy / madTPG** as pattern generator (madVR's network protocol, see below).
- **PGenerator output from HCFR**: SDR or HDR10 (with HDR metadata), color format, bit depth and
  range are set on the Pi from the app; with automatic mode the Pi switches to HDR10 when the
  reference is ST.2084 and back to SDR otherwise. 10-bit patches in HDR10.
- Raspberry Pi address in Preferences, any patch size, faster PGenerator+ answers.
- **Export HCFR's five CSV sheets** (GrayScale, Primaries, CC, General, Spectral), choosing which.
- **Automation**: other programs can ask HCFR for readings with `hcfr://` links (used by the PGC
  JVC autocalibration): `hcfr://status`, `hcfr://measure-grayscale?points=21&out=/path/name`,
  `hcfr://stop`.
- Help menu: colorimeter installation, check for updates, support.
- A DMG installer (`make-dmg.sh`).

## madVR Envy / madTPG generator

madVR's network protocol (the one calibration programs use through madHcNet on Windows),
written in Swift (`Sources/HCFRColorimeter/MadVR.swift`):

1. On the madVR Envy, or on the Windows PC running **madTPG** with *enable network access* on.
2. In **Generator**, choose **madVR Envy / madTPG** and type its IP address
   (**Generator → madVR address…**). The app connects (TCP 60562 and madVR's other ports),
   starts madTPG's test pattern mode and shows each patch with madVR's own window size setting.
3. madVR shows the patterns with its own output levels and HDR settings: set them on madVR.

## Raspberry Pi (PGenerator) generator

Same protocol as HCFR for Windows' *rPI* display mode (its `RB8PGenerator.dll`), written in Swift:

1. Start the Raspberry Pi with PGenerator, connected by HDMI to the display and on the same
   network as the Mac.
2. In **Generator**, choose **Raspberry Pi (PGenerator)**. The app finds the Pi automatically
   (UDP broadcast "Who is a PGenerator", port 1977) and connects to it (TCP port 85); the Pi screen
   shows a "connected" message with its resolution. The first time, macOS asks to allow finding
   devices on the local network: allow it (System Settings → Privacy & Security → Local Network).
3. If the Pi is not found (another subnet, Wi‑Fi isolation, VPN…), use **Generator → Raspberry Pi
   address…** and type its IP address.

*Levels* (PC 0–255 / video 16–235), *Patch size* (full field or window, on black) and *Wait before
reading* work as with a Mac display. The levels are the RGB codes sent to the Pi, as in HCFR; the
Pi's own output range (full / limited RGB, set in PGenerator) must match your display. When a run
ends or is stopped the Pi goes back to black; if the Pi restarts the app reconnects by itself.

**Generator → PGenerator output…** sets the Pi's HDMI output from the app (as PGenerator's web
page or DeviceControl): SDR or HDR10 (PQ) with its metadata (mastering primaries and luminance,
MaxCLL, MaxFALL), RGB / YCbCr 4:4:4 / 4:2:2, 8 or 10 bits, limited or full range, colorimetry.
Applying sends `CMD:SET_PGENERATOR_CONF_…` commands and restarts PGenerator. With *Choose SDR or
HDR10 automatically* on, the Pi is switched before a run to HDR10 (10 bits) when the reference
curve is ST.2084 and to SDR otherwise.

## Installing

Download `HCFR Colorimeter <version>.dmg` from the Releases page, open it and drag
**HCFR Colorimeter.app** onto the Applications folder next to it. The app is not signed with an Apple Developer ID, so
the first time macOS will block it: right-click the app → **Open** → **Open** (or allow it in
System Settings → Privacy & Security). The source code of each release is in this repository
(tag of the same version).

## Building

Requirements: macOS 14 or later and Xcode or the Command Line Tools (`xcode-select --install`).

```bash
./build-app.sh
```

This builds the colorimeter drivers and the `hcfr-meter` helper (`build-meter.sh`), then the
SwiftUI app, and creates **`HCFR Colorimeter.app`** in this folder (universal arm64 + x86_64,
ad-hoc signed). To make the installer:

```bash
./make-dmg.sh            # builds and creates "HCFR Colorimeter <version>.dmg"
./make-dmg.sh --no-build # packs the app already built
```

## Project layout

| Path | Contents |
|---|---|
| `Sources/HCFRColorimeter/` | The app (Swift / SwiftUI): interface, measurement session, color math, projects, report. |
| `meter/hcfr-meter.c` | Helper process that drives the colorimeter with HCFR's ArgyllCMS drivers. It runs apart from the app because the drivers call `exit()` on fatal errors. |
| `meter/*_compat.h` | Missing declarations needed to compile HCFR's driver code with clang on 64-bit macOS. |
| `third_party/hcfr/` | The parts of HCFR used to build the app, with two Mac-only bug fixes. See [third_party/hcfr/README.md](third_party/hcfr/README.md). |
| `Resources/` | App icon and HCFR's CCSS display corrections. |
| `build-meter.sh`, `build-app.sh`, `make-dmg.sh` | Build scripts. |

## Credits and license

- **HCFR Colorimeter** — Copyright Association Homecinema Francophone and HCFR contributors.
  https://github.com/arthur-liberman/hcfr-code · https://sourceforge.net/projects/hcfr/
- **ArgyllCMS** instrument drivers — Copyright Graeme W. Gill. https://www.argyllcms.com
- **macOS version** — Copyright (C) 2026 Jorge Velázquez.
- **Raspberry Pi (PGenerator) generator** — added in 2026 (`Sources/HCFRColorimeter/PGenerator.swift`
  and the generator code in `Session.swift` / `Views.swift`), based on HCFR's `Generator.cpp` and
  `GDIGenerator.cpp`. PGenerator is by Riccardo Biasiotto.
- **madVR** and madTPG are by madshi. The network protocol was implemented from its public
  description in DisplayCAL's `madvr.py` (Florian Höch) — no code from it is included.
- **PGenerator output commands**: as documented by quietvoid's pgen_client and PGenerator+.

This program is free software; you can redistribute it and/or modify it under the terms of the
GNU General Public License version 2 as published by the Free Software Foundation. It is
distributed in the hope that it will be useful, but **WITHOUT ANY WARRANTY**; without even the
implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See [LICENSE](LICENSE).

The color formulas in `Sources/HCFRColorimeter/ColorMath.swift` and `Colors.swift` are ported from
HCFR's C++ code (`libHCFR/Color.cpp`, `Views/MainView.cpp`, `datasetdoc.cpp`, `Export.cpp`,
`Measure.cpp`).
