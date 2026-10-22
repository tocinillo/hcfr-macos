# Changes

Each version has its DMG in [Releases](https://github.com/tocinillo/hcfr-macos/releases).

## 1.3.8

- **.chc files keep the spectra and lux values too**, both ways: the spectrum of each reading
  (spectrophotometers) and the luxmeter value are written to and read from HCFR for Windows'
  files, as Windows does (CColor versions 3, 5 and 6).

## 1.3.7

- **Projects shared with HCFR for Windows (.chc)**: File → Open Project… opens Windows .chc files
  (gray scale, near black / white, saturations, Color Checker, free measures, primaries and
  secondaries, contrast and the reference settings). Saving writes the project in both formats
  side by side, name.hcfrex and name.chc (General → "Also save in HCFR for Windows' format",
  on by default), and Save As accepts a name ending in .chc.
- **Tabs as in HCFR for Windows**: every table you open or measure (gray scale, primaries,
  saturations…) stays open as a tab above the table, with a close button. With the graph in
  **Auto**, the information panel shows the graphs of up to three open tabs side by side.

## 1.3.6

- **Reference project** (HCFR for Windows' "Set as reference"): File → Set as Reference Project
  makes the measures of the window in front the reference of every other open project (and of
  the ones opened later), which show the dE / ref and xy / ref rows and the compared curves.
  Update Reference Project takes its new measures; Clear Reference Project removes it.

## 1.3.5

- File menu: Save Project, Save Project As… (⇧⌘S), Compare with Project, the exports and the
  PDF report were missing from the menu since 1.3.2 (the project windows made macOS drop that
  menu group). They are back.

## 1.3.4

- **Measure the selected column once**: Measure → Measure Selected Column (⌘R) or the "Once"
  button: one reading of the selected gray level, color, saturation, near black / white, Color
  Checker or contrast patch (Start keeps reading it continuously, ⌘⇧R).
- **Projects in tabs**: File → New Tab (⌘T) and Open Project in New Tab…; Window → Merge All
  Windows puts the open project windows in tabs of one window.

## 1.3.3

- **Chromecast as pattern generator** (HCFR for Windows' "ccast" mode, as ArgyllCMS's libccast):
  Generator → Chromecast. Chromecasts and Google TVs are found on the network (or typed by IP).
  It uses the pattern generator receiver when available (exact patch, fast) and otherwise
  Google's default media receiver, with the patterns served by this Mac. Patch size, position
  and video levels as for the other generators. Also in the calibration wizard.
- **Interface in German, French and Italian** (Preferences → General → Language), besides
  English and Spanish, with the status and error messages too.

## 1.3.2

Everything still missing from HCFR for Windows:

- **RGB graph options** (right-click): "w/Gamma" (the channels against the target luminance, so
  the gamma error shows too, like HCFR's Absolute Y w/gamma), "Delta E curve" and "Display
  reference measure".
- **Display library from a folder of yours**: Display → "Load display library from a folder…"
  reads your CCSS / CCMX files and shows them as a tree (kind of display → technology → brand),
  with "Search display…". Nothing is bundled; the files stay yours.
- **Several projects at once**: New Window (⌥⌘N), Open Project in New Window…, Duplicate Project
  (⇧⌘D). The menus act on the window in front.
- **Export to Excel (.xlsx)**: HCFR's sheets and the table in one workbook.
- **Graph scales**: Auto-adjust, Zoom + / −, Shift Up / Down, Values…, and the average gamma line.
- **madTPG options**: disable 3D LUT, disable calibration, HDR mode, OSD.
- **Patch position** (move the patch off-center) and **black on the other displays**.
- **User defined patterns** User1–6 (Patterns menu).
- **Sensor matrix from reference values typed by hand** (HCFR's "Build manually using reference
  colorimeter").
- **Simulated sensor** (HCFR's simulated meter) to try everything without a colorimeter.
- `hcfr://measure-level` for PCG's point-by-point autocalibration.
- Spanish for all the new options.

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
