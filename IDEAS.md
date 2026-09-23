# Ideas

Features that aren't built yet, roughly ordered by effort. Every new feature should get a toggle in Settings.

## Quick wins

- **Track-change peek:** when the song changes, briefly expand the collapsed notch with the new title, then close again.
- **Charging peek:** show a short battery/charging animation in the collapsed notch when the charger is connected or removed.
- **Volume on scroll:** scroll over the notch to change the system or player volume.
- **Keyboard shortcut:** a global hotkey to open/close the notch (and to jump to a tab).
- **Like in Spotify:** Spotify's AppleScript can't change liked songs. This needs the Spotify Web API (PKCE login, `user-library-modify` scope) to save and remove tracks.

## Medium

- **Replace the system volume/brightness pop-up:** show volume and brightness changes inside the notch instead of the macOS pop-up.
- **Calendar:** next meeting with a countdown, and a "join" button for Zoom / Meet / Teams links (EventKit).
- **Timer / Pomodoro:** a countdown shown in the collapsed notch, with controls in its own tab.
- **Synced lyrics:** show the current line under the song title (e.g. LRCLIB).
- **AirPods / Bluetooth:** a connect animation with battery levels for each earbud and the case.
- **Multiple displays:** show the notch on every screen, or follow the pointer.
- **Low battery warning:** a peek when the battery drops below a threshold you choose.

## Bigger

- **Visualizer for just the player:** limit the audio tap to the music app (CATapDescription `bundleIDs`, macOS 26) so other sounds don't move the bars.
- **Notifications:** show incoming messages or app alerts in the notch.
- **Clipboard history:** a tab with recent copies.
- **Widgets:** weather, system stats (CPU / RAM / network), HomeKit controls.

## Polish

- **Auto-hide:** hide the notch in full-screen video, games or while screen sharing.
- **Auto-update** with Sparkle.
- **Signing:** a Developer ID signed and notarized build, so macOS keeps its permissions between builds.
