# RetinaAware 👁️

Save your Retina display from "burning" while using an external monitor. This tool automatically dims your MacBook's screen when you aren't using it and "wakes" it intelligently as your mouse approaches.

### Features
- **Proximity Wake:** Ramps up brightness as the mouse nears the screen border.
- **Smart Wake Extension:** Keeps the screen on longer if you return to it frequently.
- **Hotkey Force-Wake:** `Cmd + F1/F2/F3` to keep the screen active for set durations.
- **Apple Silicon Optimized:** Uses native Private Frameworks for smooth brightness transitions.

### Installation

1. **Clone & Build:**
   ```bash
   git clone https://github.com/yourusername/retina-aware.git
   cd retina-aware
   sudo make install
   ```

2. **Grant Permissions:**
   This tool needs to monitor mouse movement and register global hotkeys.
   - Go to **System Settings > Privacy & Security > Accessibility**.
   - Click the **+** button.
   - Press `Cmd + Shift + G` and type `/usr/local/bin/retina-aware`.
   - Enable it.

3. **Enable Auto-Start (Launch Agent):**
   To have it start automatically when you log in:
   ```bash
   make start-agent
   ```

### Hotkeys
- `Cmd + F1`: Wake for 1 minute
- `Cmd + F2`: Wake for 5 minutes
- `Cmd + F3`: Wake for 10 minutes

### Configuration
Adjust the `Config` struct in `Sources/RetinaAware/main.swift` to change timings, thresholds, or brightness levels, then run `sudo make install` again.

### License
MIT
