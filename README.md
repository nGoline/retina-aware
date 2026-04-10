# RetinaAware

Save your Retina display from "burning" while using an external monitor. This tool automatically dims your MacBook's screen when you aren't using it and "wakes" it intelligently as your mouse approaches or via customizable hotkeys.

## Features
- **Universal Proximity Wake:** Ramps up brightness as the mouse nears the Retina display, regardless of monitor arrangement.
- **Smart Wake Extension:** Keeps the screen on longer if you return to it frequently (exponential backoff).
- **Customizable Hotkeys:** Record your own keys (e.g., `Cmd + F1`) to force the screen active for set durations.
- **Visual Status Icon:** Menu bar icon changes state:
  - ☀️ **Sun:** Active
  - 🌙 **Moon:** Dimmed
  - ☁️ **Cloud:** Disabled
- **Apple Silicon Optimized:** Uses native private frameworks for smooth, flicker-free transitions.

## Installation

### Download (Recommended)
Download the latest `RetinaAware.zip` from the [Releases Page](https://github.com/ngoline/retina-aware/releases). Unzip and move `RetinaAware.app` to your `/Applications` folder.

### Build from Source
If you have Swift installed:
```bash
git clone https://github.com/ngoline/retina-aware.git
cd retina-aware
sudo make install
```

## Permissions
Since this tool monitors mouse movement and registers global hotkeys, you must grant it permissions:
1. Go to **System Settings > Privacy & Security > Accessibility**.
2. Add and enable **RetinaAware**.

## Configuration
Click the icon in the menu bar to open the settings panel. You can adjust:
- **Active/Dimmed Brightness** levels.
- **Approach Threshold** (how close the mouse needs to be to trigger).
- **Grace Periods** and **Wake Extension** multipliers.
- **Hotkeys** and their respective durations.

## License
MIT © Níckolas Goline 2026
