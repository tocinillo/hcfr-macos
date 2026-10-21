# HCFR Colorimeter for macOS

A native macOS version of **HCFR Colorimeter**, focused on calibrating TVs and monitors (especially
CRT TVs) with a colorimeter and a calibration DVD / external pattern generator.

> **Unofficial port.** This project is not affiliated with or endorsed by the HCFR project. It is
> built from HCFR's open-source code: https://github.com/arthur-liberman/hcfr-code

- Mac version by Jorge Velázquez, Mazatlán, México
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

## Installing

Download `HCFR-Colorimeter-<version>-macOS.zip` from the Releases page, unzip it and move
**HCFR Colorimeter.app** to Applications. The app is not signed with an Apple Developer ID, so
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
ad-hoc signed).

## Project layout

| Path | Contents |
|---|---|
| `Sources/HCFRColorimeter/` | The app (Swift / SwiftUI): interface, measurement session, color math, projects, report. |
| `meter/hcfr-meter.c` | Helper process that drives the colorimeter with HCFR's ArgyllCMS drivers. It runs apart from the app because the drivers call `exit()` on fatal errors. |
| `meter/*_compat.h` | Missing declarations needed to compile HCFR's driver code with clang on 64-bit macOS. |
| `third_party/hcfr/` | The parts of HCFR used to build the app, with two Mac-only bug fixes. See [third_party/hcfr/README.md](third_party/hcfr/README.md). |
| `Resources/` | App icon and HCFR's CCSS display corrections. |
| `build-meter.sh`, `build-app.sh` | Build scripts. |

## Credits and license

- **HCFR Colorimeter** — Copyright Association Homecinema Francophone and HCFR contributors.
  https://github.com/arthur-liberman/hcfr-code · https://sourceforge.net/projects/hcfr/
- **ArgyllCMS** instrument drivers — Copyright Graeme W. Gill. https://www.argyllcms.com
- **macOS version** — Copyright (C) 2026 Jorge Velázquez.
- **Raspberry Pi (PGenerator) generator** — added in 2026 (`Sources/HCFRColorimeter/PGenerator.swift`
  and the generator code in `Session.swift` / `Views.swift`), based on HCFR's `Generator.cpp` and
  `GDIGenerator.cpp`. PGenerator is by Riccardo Biasiotto.

This program is free software; you can redistribute it and/or modify it under the terms of the
GNU General Public License version 2 as published by the Free Software Foundation. It is
distributed in the hope that it will be useful, but **WITHOUT ANY WARRANTY**; without even the
implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See [LICENSE](LICENSE).

The color formulas in `Sources/HCFRColorimeter/ColorMath.swift` and `Colors.swift` are ported from
HCFR's C++ code (`libHCFR/Color.cpp`, `Views/MainView.cpp`, `datasetdoc.cpp`, `Export.cpp`,
`Measure.cpp`).
