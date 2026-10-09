# Project Progress & Feature Roadmap

## Completed / Active Features

### Feature 1: Main Menu Bar Icon Temperature Readout Replacement (Active)

#### Overview
Replace or augment the main menu bar icon (traditionally the Vorssaint planet/galaxy style icon) with a customizable live temperature readout directly in the menu bar.

#### Settings & Configuration
- **Main Icon Replacement Option**: Toggle setting to replace the standard menu bar icon with temperature readouts.
- **Display Layout**:
  - `Stacked` (Default): Top number and bottom number stacked vertically.
  - `Side-by-Side`: Top and bottom numbers displayed horizontally adjacent to each other.
- **Sensor Selection**:
  - Top / First Sensor: Default is **Hottest CPU**.
  - Bottom / Second Sensor: Default is **Hottest GPU**.
  - Flexible sensor assignment allowing selection of available hardware temperature metrics (CPU, GPU, Battery, etc.).

#### Look & Feel
- **Stacked Layout**: Two compact monospaced numbers (e.g. `45°` on top, `42°` on bottom) styled to align cleanly with macOS menu bar height and typography standards.
- **Side-by-Side Layout**: Monospaced horizontal numbers separated cleanly (e.g. `45° 42°`).

#### Click Action
- Clicking the temperature readout status item opens/toggles the regular Vorssaint main app panel (homepage).
- Maintains full compatibility with standard main menu bar status item functionality.

---

## Future Planned Features Roadmap

### Feature 2: Detailed Hardware Sensors Detail Panel
- Expandable popup view listing individual SSD/NAND temperatures, dual battery temperature sensors, average vs. hottest CPU cores, average vs. hottest GPU, and voltage/power draw statistics.

### Feature 3: Customizable Temperature Threshold Alerts & Notifications
- User-configurable warning/critical temperature thresholds with banner notifications and color indicators in the menu bar readout.

### Feature 4: Extended Menu Bar Temperature Styling & Sensor Multi-Selection
- Color-coding temperatures based on heat thresholds (e.g. green/yellow/red).
- Customizable font sizes and sensor label options for multi-monitor setups.
