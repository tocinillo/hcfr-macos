# Changes

Each version has its DMG in [Releases](https://github.com/tocinillo/hcfr-macos/releases).

## 1.3.22

- **Hardened the .chc reader** (in the spirit of HCFR 4.1's MATH-001/002): array lengths read from
  the file are now bounded, so a corrupt or truncated .chc can't crash the app on a bad count.

## 1.3.21

- **Fixed CIELUV u'v' Delta E (ported from HCFR 4.1, finding MATH-005)**: the u' denominator used
  x where y is required, which under-reported the error of saturated colors by up to several dE in
  every u'v'-based Delta E (the grayscale ΔE among them). Now matches the canonical CIE 1976 u'v'.

## 1.3.20

- **Renamed to "HCFR for macOS"** (window titles, About, reports and the app name). The project
  files, settings and imported ArgyllCMS data are unchanged, so existing projects keep working.

## 1.3.19

- **Opens older .hcfrex projects again**: the reader is now tolerant — it loads the measurements
  and skips any legacy or unreadable block instead of refusing the whole file (fixes a regression).
- **Summary tab: editable Comments**, as in HCFR for Windows. Notes typed there are saved with the
  project (in both .hcfrex and .chc).

## 1.3.18

- **Right-click on a tab → Close all tabs** (the gray scale stays, as one table is always shown).

## 1.3.17

- **CIE diagram menu as in HCFR for Windows**: Display saturations, Display saturations targets,
  Display color checker measures, Display color checker targets and Display free measures, each on
  its own (they were a single option).
- **Graph Scale menus**: HCFR's fixed scales — Luminance 0-100 %, Gamma 1-3, Saturation 0 / +100 %,
  -100 / +100 % and -20 / +20 %.
- **Right-click on a tab → Close other tabs.**

## 1.3.16

- **Wizard → White balance & gamma, Multipoint**: with many gray levels the level buttons now
  scroll instead of widening the step past the window, so the "2 points / Multipoint" switch stays
  visible and you can go back to 2 points.

## 1.3.15

- **Color Checker → LG_540_2016, LG_540_2017, LG_1000_2017 and LG_4000_2017**: HCFR for Windows'
  LG HDR base tone curve sets, with LG's fixed targets against the measured peak white (they
  were missing on the Mac). Also in .chc files.
- **Generator menu: Constant APL (background), Pattern intensity and Display triplets**, HCFR's
  generator options: with a window patch the background keeps the average picture level
  constant (5–50 %), the color patches can be shown at 75 % or 50 % amplitude, and the R:G:B
  codes can be drawn on the patch.
- **Color Checker → Verification**: RGB cube sets of 64, 125, 216 and 729 patches (every
  combination of R, G and B levels), measured as a User defined set, so they also open in HCFR
  for Windows. The PDF report gives the share of patches under ΔE 1, 2 and 3 and the worst ones.

## 1.3.14

- **Edit → Undo / Redo (⌘Z / ⌘⇧Z) of measures**, edits and deletes, as HCFR for Windows (up to
  100 steps; while typing in a field, ⌘Z still undoes the typing).
- **View → Luminance (luxmeter)** (⌥⌘L): HCFR's floating window with the luxmeter's live value
  in Lux or Ft-cd ("++++" when out of range).
- **Right-click on a table tab**: Activate tab, Activate tab on all documents, Duplicate tab,
  Open tab in a new window (a copy of the project showing that table), Close tab.
- **File → Duplicate Project…** asks which tables to copy to the new project.
- **File → Add to Excel Workbook…**: adds the sheets to an existing .xlsx (also one saved by
  Excel), named with the time, so measures taken at different times sit side by side.
- **File → Page Setup…**
- **Preferences → Reset to Defaults…** (the measures are kept).
- **HCFR for Windows' function keys** in the Measure menu: F2 gray scale, F3 primaries, F4
  primaries and secondaries, F5 gray scale and colors, ⇧F5 Full Tilt Boogie, F7 single
  measurement, F8 continuous measurement.
- Additional Patterns now always acts on the project of the window in front.

## 1.3.13

- **Patterns → Additional Patterns… (⌘⇧P)**, as HCFR for Windows: Black +, colors, dot patterns
  (white / red / green / blue), horizontal and vertical lines, B&W and color shadings, black and
  white level tests, color bars, convergence grid, geometry, and the picture sets (grid
  analysis, test picture bench, iris & definition, ANSI 1 / ANSI 2 contrast, contrast boxes),
  plus EIA 1956, SMPTE 75 % and the calibration picture. While a pattern is shown, + / − (or
  Page Up / Down) change the level, number of dots or picture, * (or Home) resets it, Space
  switches thin / thick dots and lines, ESC closes it.
- **Right-click on any graph** opens its options, as in HCFR for Windows, plus Save…:
  - Luminance and gamma: Luminance / Red / Green / Blue curves, display reference, display
    reference measure, average gamma.
  - Near black / near white: Absolute Y, luminance % or L*, logarithmic mode, R/G/B curves,
    reference.
  - Saturation shift: primary and secondary colors, each color on or off, reference.
  - Color temperature: reference and reference measure.
  - Free measures: luminance, x/y, ΔE and color temperature curves, and the last 10 / 20 / 50
    measure points.
- **Graph parameters**: line thickness (1–4) and display dots, in the graph menu.
- **Save graph** now offers PNG, JPEG or BMP and the image size (up to 1920 × 1080).

## 1.3.12

- **One project format for Mac and Windows: .chc is now the default.** Projects are saved in
  HCFR for Windows' format, and the same file also carries everything the Mac version saves
  (display and meter used, spectra, lux values, user Color Checker…), so it opens on Windows and
  nothing is lost on the Mac. Older .hcfrex projects still open, and Preferences → Advanced →
  Project file format can still save .hcfrex only or both.
- **File → Open Recent**, with Clear Menu.

## 1.3.11

- **.chc for Windows: correct gamma, Y targets and ΔE.** HCFR for Windows takes the white of
  the gray scale from the on/off contrast white (it fills it in when it measures a gray scale);
  the .chc files now carry it (100 % white, and 0 % or the override black), so Windows shows
  the same gamma, targets and ΔE as the Mac instead of gamma 1.00 and larger ΔE.

## 1.3.10

- **Updates from the app**: when a new version is out (checked at start-up, or with HCFR
  Colorimeter → Check for Updates… / Help → Updates), "Install and Relaunch" downloads it,
  replaces the app and opens the new version — no DMG to open and nothing to drag to
  Applications. The release notes are shown first. Checking at start-up is now on by default
  (Preferences → General → Check for updates).

## 1.3.9

- **Project file format** in Preferences → Advanced: save projects in both formats (default:
  name.hcfrex and name.chc side by side), Mac only (.hcfrex) or Windows only (.chc). The save
  dialog no longer asks for an extension.

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
