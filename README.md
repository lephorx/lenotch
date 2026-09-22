# LephorNotch

A macOS notch companion in SwiftUI. The notch stays black where the hardware cutout is and
melts into Liquid Glass as it extends past it, so the panel reads as the notch *growing*
rather than a window sitting under it.

![requires macOS 26+](https://img.shields.io/badge/macOS-26%2B-black) ![Swift 6](https://img.shields.io/badge/Swift-6-orange)

## What it does

| | |
|---|---|
| **Now Playing** | Spotify and Apple Music — artwork, scrubbing, shuffle/repeat, transport. Artwork colours tint the glass. |
| **Calendar** | Month grid with per-day event dots, plus the agenda for the selected day (EventKit). |
| **Shelf** | Drop files on the notch; drag them back out anywhere. Survives relaunch via security-scoped bookmarks. |
| **Battery** | Percentage, charge state, time remaining, Low Power Mode (IOKit). |
| **System HUD** | Custom volume and brightness readouts rendered inside the notch, replacing the stock macOS HUD. |

Two appearances: **Liquid Glass** (black at the top, progressively transparent glass below)
and **Pure Black**.

## Build

```bash
./build.sh --run      # compile, bundle, ad-hoc sign, launch
CONFIG=debug ./build.sh
```

Output is `dist/LephorNotch.app`. It runs as a menu-bar accessory (`LSUIElement`), so there's
no Dock icon — use the status item or the notch itself.

## Permissions

The app asks for these on first use. All are optional; each feature degrades on its own.

- **Automation** (Spotify / Music) — playback control and track info.
- **Calendars** — the calendar tab.
- **Accessibility** — lets the app capture the volume/brightness keys so macOS doesn't draw
  its own HUD next to ours. Without it the keys still work and the HUD still appears, but the
  system HUD shows too.

Settings › *Hide the built-in macOS HUD* additionally retires `OSDUIHelper` on a timer, which
is the only way to keep the stock overlay off screen — macOS relaunches it on demand.

## Notes on the implementation

- **The window never resizes.** The panel is always as large as the widest state; only the
  SwiftUI content animates. Resizing an `NSWindow` mid-spring is what makes notch apps stutter.
- **`NotchShape`** draws concave shoulders at the top and normal rounded corners at the
  bottom, with both radii animatable.
- **Brightness** has no public API on Apple Silicon. `DisplayServices` is `dlopen`ed, so a
  missing symbol degrades to "brightness unavailable" instead of failing to launch.
- **The spectrum bars are decorative.** macOS won't hand you another app's audio without a
  virtual device, so they're a seeded random walk, not an FFT.
- **Ad-hoc signing uses a stable identifier** (`com.lephor.notch`) so TCC grants survive
  rebuilds instead of re-prompting on every launch.

## Layout

```
Sources/LephorNotch/
  App/        main, AppDelegate, NotchPanel (borderless non-activating NSPanel)
  Core/       geometry detection, view model, settings, theme, colour extraction
  Services/   media, battery, calendar, audio, brightness, HUD key tap, shelf
  UI/         notch shape & background, collapsed + expanded content, panels
```
