# Vorssaint: Unified Mac Utility — Feature & Implementation Roadmap

**Document status:** Implementation specification for AI coding agents  
**Prepared:** 2026-10-08  
**Primary repository:** <https://github.com/vorssaint/vorssaint-utils>  
**Target platform:** Existing Vorssaint target: macOS 14+ on Apple Silicon unless a feature is explicitly marked otherwise.

## 0. Product goal

Evolve Vorssaint into one lightweight, native Mac utility that covers the useful functionality of:

- **Stats** — system monitoring, temperature/sensor readouts, utilization, histories, menu-bar readouts and alerts.
- **BetterDisplay** — display information and controls, brightness, resolution, refresh rate, HiDPI/scaling, display layouts, profiles, and advanced display workflows where technically and legally feasible.
- **AlDente** — charge limiting and battery-care automations, including the 18 battery features in the original request plus related telemetry and actions.
- **Existing Vorssaint features** — retain the existing modular feature catalog, native user interface, system monitor, display/brightness tools, battery/power information, and the rest of the application.

The goal is **feature consolidation with measured resource usage**, not reducing process count at any cost. One app can still consume more RAM or CPU than several small apps if it creates duplicate samplers, continuously performs expensive work, captures screen content in the background, or runs a privileged daemon unnecessarily.

### Product requirements

1. Build on the current repository. Do not replace the architecture wholesale or rewrite working features just to make the new modules fit.
2. Use native Swift/AppKit/SwiftUI and macOS frameworks where suitable. Do not add a Python runtime, Electron, a web-based UI, or a second always-running runtime.
3. Reuse existing system-monitor, sensor-selection, battery, display and feature-catalog code after inspecting it. Avoid duplicate implementations.
4. Keep features independently enableable. A disabled feature must not start polling, retain observers, keep helper processes active unnecessarily, or remain in the user interface as a broken control.
5. Prefer documented/public APIs. For operations that require reverse-engineered hardware protocols or private APIs, implement only after documenting hardware coverage, compatibility risk, and a tested fallback.
6. Hardware-sensitive operations must verify the result, not merely report that a command was sent.
7. Do not claim parity with another app just because a control exists in the UI. Every feature needs implementation evidence and a stated support matrix.
8. Do not bypass a third-party app's Pro checks, copy proprietary implementation code, or rebrand third-party code as Vorssaint. Follow the license of any code that is reused.
9. The first release should prioritize the requested CPU/GPU temperature view, common display controls, and a safe charge limiter. Advanced display emulation and battery automation come later.
10. The app must remain useful when a feature is unsupported by the current Mac or macOS release: show a clear “Not supported on this Mac” explanation, not a fake or nonfunctional control.

## 1. Repository rules the coding agent must follow

Before editing anything, inspect the current branch, working tree, build setup, feature catalog, `Sources/Vorssaint/App`, `Core`, `Services`, `UI`, `Support`, existing system-monitor sensor code, display/brightness services, battery telemetry, localization, and tests. Search for existing implementations before adding new files.

The repository's contributor guidance says it targets macOS 14+ and Apple Silicon, uses `build.sh` rather than an Xcode project for the official build, and has no external package dependencies by default. Preserve those conventions unless there is a documented, measured reason to change them.

Use the existing commands and verify their current behavior before assuming a command or test target:

```bash
./build.sh --dev
./build/VorssaintDeveloper --selftest
./build.sh --test
./build.sh --list-tests
```

For a focused test suite, use the repository's documented `./build.sh --test-suite=NAME` flow. Also build the optimized variant and run its self-test when the final change affects app startup, bundled resources, runtime behavior, or UI. A test-only build passing does not prove the complete app builds. Build with no new warnings.

Keep changes incremental and focused. Do not bump the app version or publish a release as part of this work. Update localizations, feature catalog metadata, settings backup coverage, permissions documentation, and tests whenever a feature requires them.

### Required first deliverable from the coding agent

Before implementation, produce a short audit report containing:

- Current modules/files that already satisfy each requested feature.
- Gaps that require new code.
- Existing APIs/data sources and polling intervals.
- Existing permissions and helper processes that can be reused.
- A risk table for charge-control methods, advanced display control, and any private APIs.
- Baseline memory/CPU measurements (or exact reasons they cannot be collected in the agent's environment).
- The proposed first small vertical slice.

Do not start by writing a massive “everything” change. Use the phases in Section 7.

---

## 2. Architecture requirements

### 2.1 Native, modular, shared-service design

Keep the main interface and feature modules in the existing native application. New functionality should be an extension of the current architecture:

- **Feature catalog / settings:** Feature enabled state, user-facing configuration, availability, permissions, and settings backup.
- **Shared telemetry service:** One source of truth for system, sensor, battery and power snapshots. UI modules subscribe to snapshots instead of starting their own samplers.
- **Battery controller:** A small, explicit state machine that calls a capability-checked hardware adapter. Battery UI, Shortcuts, schedule actions, and menu-bar icons must all use the same controller.
- **Display controller:** One display inventory and controller for queries and changes. The menu-bar panel, Settings, saved layouts and Shortcuts must use the same service.
- **Feature-owned UI:** Each module controls its own panel/settings and is lazy-loaded or activated only when its feature is enabled.
- **Optional privileged helper:** Introduce only if reliable charging control requires it. Keep the user-facing app unprivileged; use a narrowly scoped, authenticated local IPC interface rather than unrestricted root shell commands.
- **Diagnostics:** Record capability discovery, failed operations, fallback choices, and action history locally without collecting analytics or personal data.

### 2.2 Shared telemetry model

Inspect and reuse existing types first. If the existing models cannot represent the information needed, add a small normalized model instead of inventing several competing ones. Conceptual shape:

```swift
struct TelemetryReading {
    let id: String              // stable semantic identifier, not a display label
    let label: String
    let category: Category      // cpu, gpu, battery, power, fan, memory, etc.
    let value: Double
    let unit: String
    let source: Source           // native API, SMC/IOKit, estimated, unavailable
    let timestamp: Date
    let quality: Quality        // measured, estimated, stale, unavailable
}
```

This is a design sketch, not a mandate to duplicate an equivalent type already in the codebase.

Requirements:

- Cache each sampled value centrally; multiple UI widgets must reuse the same snapshot.
- Track freshness. Never show stale values as if they were current.
- Keep source/provenance and units attached to the values, especially for temperature, battery percentages and power flow.
- Distinguish measured telemetry from calculated/estimated telemetry.
- A failed sensor read must become an unavailable/stale state; it must not silently become zero.
- Avoid a polling timer per row, widget, or feature. Use a shared sampler and publish change notifications only when useful values change.
- Poll slowly when panels are hidden and a reading is not used; stop feature-specific work when disabled. Preserve a reasonable update rate for visible live controls.
- Do not run shell processes repeatedly for telemetry that can be read through an existing native service.

### 2.3 Swift implementation conventions

- Follow the repository's current naming, source-file headers/SPDX convention, concurrency patterns, localization patterns, error types and testing style.
- Keep UI rendering separate from hardware operations. Views must not contain SMC, IOKit, CoreGraphics configuration or persistence logic.
- Avoid force unwraps and unhandled task errors in hardware-dependent code.
- Use structured concurrency or the existing repository pattern; do not create unbounded detached tasks.
- Ensure observers, timers, notification registrations and display callbacks are invalidated when features are disabled or the owning service shuts down.
- Debounce rapid user input (for example, a charge-limit text field) and apply a validated value once, not on every keystroke.
- Use small protocols around hardware adapters so the state machine and UI can be tested with fake implementations.
- No broad refactors unrelated to this feature roadmap.

### 2.4 Battery hardware capability adapter — mandatory safety boundary

Charging behavior control is the highest-risk part of this project. Reading battery state is not the same operation as changing charging behavior. Do not assume macOS provides a stable public API to set arbitrary hardware charging limits on every Apple Silicon Mac.

Before implementing charge writes:

1. Audit current Vorssaint battery code and its documented data sources.
2. Determine exactly which model/OS combinations can be read and controlled. Record the Mac identifier, macOS version, battery/charger path, and the evidence used to classify support.
3. Identify whether the needed operation depends on SMC/IOKit private or reverse-engineered behavior. Do not invent register/key names or copy undocumented assumptions without device-specific evidence.
4. Prefer a documented interface. If there is no supported write path, isolate the experiment behind an explicitly experimental adapter and do not present it as stable.
5. Read back state after each write and verify the actual charging/discharging state over time.
6. If a command fails or its result cannot be verified, move to `unknown/error`, stop retrying aggressively, and tell the user. Never display “limit active” based solely on the desired preference.
7. Never leave the battery in an unknown or unintended charge-control state after a failed transition. Define and test a recovery procedure before enabling control by default.

Create a per-model capability matrix. Unsupported models should retain read-only telemetry. Do not attempt to force this functionality to work across every MacBook generation in the first release.

### 2.5 Privileged helper rules

If a helper is needed to preserve charge control after the main app closes:

- Use Apple's supported Service Management approach appropriate to the required privilege, and test registration, disabled-helper behavior, upgrades, removal, user switching and OS startup.
- Use a signed helper and a narrow local XPC protocol with a fixed method allowlist, typed arguments, strict percentage/range validation and caller validation.
- Never expose arbitrary command execution, shell strings, file paths, scripts or generic “write arbitrary SMC key” methods to the UI process.
- Avoid a helper if the hardware retains the desired state without it.
- Clearly explain what stays active when the user quits Vorssaint and give a Settings control to disable/unregister the helper.
- Log only minimal local diagnostic events; do not upload them.
- Ensure clean uninstall returns service registration and persistent state to the documented normal state.

### 2.6 State and conflict handling

All battery actions, UI labels, menu-bar icons and Shortcuts should derive from one canonical state machine. Suggested states include:

- `unavailable`
- `idleOnBattery`
- `chargingToLimit`
- `holdingAtLimit`
- `topUpActive`
- `manualDischargeActive`
- `automaticDischargeActive`
- `heatProtectionPaused`
- `sleepTransitionPause`
- `calibration(stage:)`
- `operationFailed`

Define priority rules before coding. At minimum:

1. Hardware/thermal safety and low-battery guards must not be overridden by a scheduled job or user-interface animation.
2. Heat Protection must remain active during Calibration Mode. Do not reproduce another app's decision to disable a thermal guard just to speed up a cycle.
3. Top Up is a temporary override, not a permanent replacement for the saved charge limit.
4. Manual and automatic discharge must never run simultaneously.
5. If the adapter is unplugged, stop discharge/sleep-prevention behavior and revert Top Up as specified.
6. A settings value is a target; it is not proof that hardware enforcement succeeded.
7. On wake, login, user switch, helper restart or charger change, reconcile the desired state with the current hardware state before issuing any new action.

---

## 3. Stats parity — monitoring features

**Principle:** extend the existing Vorssaint system monitor first. Several capabilities already appear to exist, including CPU/GPU usage, temperatures, battery health/power, energy-hungry-app visibility, fan tools, menu-bar readouts, network telemetry and alerts. Verify exact coverage and quality before marking items complete.

### ST-01. CPU and GPU utilization — reuse/verify

**Description:** Show current CPU and GPU utilization in the system monitor and, optionally, compact menu-bar readouts.

**Build instructions:**

- Reuse the existing system monitor data path. Inspect its sampling cadence and ensure one collector serves the dashboard, menu bar and history charts.
- Preserve existing per-core or aggregate breakdowns if available. If per-core data is not already supported, treat it as a separate optional enhancement rather than a prerequisite for GPU/CPU temperatures.
- Make unsupported readings explicit. Avoid expensive process enumeration at a high cadence when the panel is hidden.

**Acceptance criteria:** values update while visible; disabling the module stops feature-specific work; no second independent poller is created; tests cover unavailable samples and stale data.

### ST-02. Hottest CPU and GPU temperatures — requested priority

**Description:** Show the hottest available CPU-related and GPU-related temperature sensor readings, with a detailed sensor view for debugging.

**Build instructions:**

- Reuse the repository's sensor enumeration, sensor-selection and system-monitor code (including existing sensor selector logic) instead of embedding a new sensor table inside the UI.
- Build a sensor classification layer that groups sensor identifiers into CPU, GPU, battery, memory/SoC, skin/palmrest, power and other/unknown categories. Use actual sensor metadata/known identifier mappings; do not guess from arbitrary substrings without a fallback review.
- Compute the maximum **among valid, fresh sensors in the category**. Do not average the sensors to determine a “hottest” value.
- Label the sensor and expose its identity in the detailed view. If classification is uncertain, put the sensor under “Other” until the mapping is verified.
- Avoid claiming that a reading is a diagnostic of hardware health. It is a software-accessible sensor reading.
- Where practical, display a short sparkline/history without collecting a large history when disabled.

**Acceptance criteria:** hottest CPU/GPU values match a calculation from the fresh sensor snapshot; unavailable categories show “Unavailable” rather than 0°C; a sensor update populates every UI surface from the same snapshot.

### ST-03. Sensor browser: temperature, voltage and power

**Description:** Provide a detailed, searchable inventory of supported sensors and their readings, grouped by category.

**Build instructions:**

- Reuse current sensor enumeration. Add grouping/filtering and sort by current value only for compatible units/categories.
- Keep the sensor's source identifier for diagnostics but use understandable labels in the ordinary UI.
- Do not attempt to interpret all sensor values as temperatures; units and sensor types must remain explicit.
- Add export/copy of a local diagnostics snapshot only after excluding identifiers/secrets that are not needed.

**Acceptance criteria:** values include units and updated-at status; unsupported or unreadable sensors are handled safely; category filtering is deterministic.

### ST-04. Temperature and utilization history graphs

**Description:** Display short rolling histories for selected CPU/GPU temperature, CPU/GPU load, memory pressure and battery telemetry.

**Build instructions:**

- Add a bounded in-memory time-series buffer. Persist history only if the user explicitly enables it and the storage/retention policy is documented.
- Downsample when moving away from recent time windows; do not append indefinitely to an unbounded array.
- Keep graphing optional and use native drawing/SwiftUI shapes already used by the app.

**Acceptance criteria:** memory usage remains bounded after an all-day run; turning off history releases the buffer; values from missing intervals appear as gaps instead of false zeroes.

### ST-05. Memory usage and pressure — reuse/verify

**Description:** Provide memory use, memory pressure state and relevant system memory figures.

**Build instructions:**

- Reuse existing monitor code and labels. Verify pressure state is presented separately from raw usage.
- Do not add high-frequency process-by-process memory scans when only aggregate information is needed.

**Acceptance criteria:** consistent values across monitor and menu-bar UI; stale/unavailable readings are represented consistently.

### ST-06. Disk capacity and disk activity

**Description:** Show available/used disk space and supported activity/throughput readings.

**Build instructions:**

- Check current implementation for disk usage and I/O data before adding anything.
- Separate filesystem capacity from disk I/O throughput. Use the appropriate native source for each.
- Query slowly for capacity changes; use the existing monitoring cadence for live throughput.

**Acceptance criteria:** volumes are identified clearly; ejected volumes disappear; disk capacity is not polled at the same rapid rate as CPU utilization.

### ST-07. Network throughput and traffic totals — reuse/verify

**Description:** Show upload/download rates, cumulative session traffic, local IP information and an optional speed test.

**Build instructions:**

- Reuse the existing Network feature if it already provides these items. Do not create a second network sampler.
- Calculate rates from byte-counter deltas and monotonic elapsed time. Handle interface changes, counter resets, VPN interfaces and sleep/wake.
- Keep the speed test user-triggered. Make clear that it sends test traffic to a network endpoint; do not run it in the background.

**Acceptance criteria:** rate resets safely when a network interface changes; the module does not perform network tests unless the user starts one.

### ST-08. Battery, health and power telemetry — reuse/extend

**Description:** Present macOS battery level, charging state, adapter state, cycle count, maximum/nominal capacity and health-related fields available from supported sources, plus battery temperature and power values when available.

**Build instructions:**

- Extend existing battery telemetry rather than reading a second data source for each widget.
- Mark capacity/health as estimates or system-reported values where applicable. Do not infer precise remaining battery life when the data source does not support it.
- Keep the AlDente-style hardware percentage as a separate field; never silently substitute it for macOS's percentage.

**Acceptance criteria:** source and units are clear; unavailable values render as `--`/Unavailable; no “100% health” is fabricated when the source is missing.

### ST-09. Fan RPM and fan control — supported hardware only

**Description:** Read fan speeds and, only where robustly supported, allow manual speed or a temperature-based curve.

**Build instructions:**

- Inventory fan-control support on the actual hardware target. The upstream Stats README describes its fan-control component as not maintained; do not consider that code a stable dependency without review.
- Read-only fan RPM is lower risk than writing fan targets. Implement read-only telemetry first.
- Manual control must have explicit enable/disable, safe limits, a failsafe to return control to system behavior on app/helper failure, and a visible indication while active.
- Do not add fan write support to fanless machines, or expose a control where fan identifiers cannot be validated.

**Acceptance criteria:** app quit, crash, helper removal and sleep/wake each return fans to a documented safe policy; write controls are hidden on unsupported hardware; stress tests confirm no stuck manual mode.

### ST-10. Bluetooth devices

**Description:** Show a small readout of connected Bluetooth device names/status where allowed by system APIs.

**Build instructions:**

- Use existing macOS Bluetooth APIs and request permissions only if needed.
- Keep it optional and avoid continuous device discovery/scanning just to draw a menu-bar icon.

**Acceptance criteria:** no background scan when the module is disabled; permission denial produces a clear lightweight fallback.

### ST-11. Multiple time-zone clock

**Description:** Provide optional clocks for selected time zones in the menu bar/panel.

**Build instructions:**

- Use Foundation date/time-zone support; no external service or network lookup.
- Persist selected time-zone identifiers, not current offsets. Respect locale and daylight-saving transitions.

**Acceptance criteria:** tests cover daylight-saving transitions and non-whole-hour offsets.

### ST-12. Configurable menu-bar readouts and widgets

**Description:** Let the user choose which values appear in the menu bar and compact panel, reorder/hide widgets, and select compact/expanded presentations.

**Build instructions:**

- Integrate into the existing layout/feature catalog system. Reuse the same telemetry snapshot as the expanded monitor.
- Each widget needs a valid unavailable state and a low-cost compact rendering.
- Persist preferences through the current settings backup mechanism.

**Acceptance criteria:** reordering and hiding do not restart hardware collectors unnecessarily; disabled widgets subscribe to no unnecessary high-frequency updates.

### ST-13. Resource and thermal alerts

**Description:** Optional notifications for sustained high CPU load, high temperature, memory pressure, low disk space and low battery.

**Build instructions:**

- Reuse the existing alert service and permission flow.
- Use configurable thresholds and a persistence window so a single noisy sample does not spam notifications.
- Add cooldown/de-duplication and a clear explanation when notifications permission is denied.
- Use existing battery Heat Protection for charging control; this alert feature must not take over battery state.

**Acceptance criteria:** tests cover threshold crossing, recovery, cooldown and unavailable sensor cases; no alerts are generated for disabled rules.

---

## 4. BetterDisplay parity — display features

**Important scope note:** implement the commonly used display controls first. BetterDisplay contains advanced functions (virtual displays, deep HiDPI behavior, certain HDR operations, EDID overrides, DDC/CEC and streaming) that may depend on undocumented/private APIs, particular hardware, OS-specific behavior or its Pro terms. “Public GitHub repository” does not by itself grant permission to copy every implementation or reproduce Pro functionality. Do not bypass license checks. Use a clean native implementation, or an explicitly optional documented integration where appropriate.

### BD-01. Display inventory and diagnostics

**Description:** List internal/external displays with current mode, logical and physical dimensions, refresh rate, rotation, scale/backing scale, HDR/color information when available, vendor/product/name, connection type, and stable identity where possible.

**Build instructions:**

- Use the existing display inventory and brightness controller first.
- Use public CoreGraphics/AppKit APIs for active displays and available modes. The public `CGDisplayMode` API exposes dimensions and refresh rate for a mode; investigate current deprecation/compatibility guidance before relying on older APIs.
- Use stable hardware identity where available. Do not persist a transient display ID as the only identifier; IDs can change across reconnect/reboot.
- Clearly distinguish logical points, output pixels and “looks like” HiDPI scaling. Do not call them all “resolution.”
- Optional diagnostics may show EDID/vendor/product/connection information only when the OS exposes it reliably.

**Acceptance criteria:** unplugging/reconnecting a monitor updates the inventory; identical model displays can be distinguished when their hardware serials permit it; missing metadata does not crash the UI.

### BD-02. Per-display brightness controls — reuse/extend

**Description:** Set brightness independently for each display, including the built-in display and supported external monitors.

**Build instructions:**

- Reuse Vorssaint's existing display/brightness module and avoid duplicating brightness state.
- Prefer the normal system brightness API for built-in displays where available.
- For supported external displays, investigate DDC/CI only through a validated transport. Do not assume every USB-C, HDMI, DisplayLink or dock connection exposes DDC controls.
- Use software dimming as an explicitly labelled fallback, not as if it changed the panel's hardware brightness. If software dimming is used, explain its visual/contrast limitations.
- Provide keyboard adjustments, menu-bar sliders and per-display remembered preferences only where the underlying control supports them.

**Acceptance criteria:** each control shows whether it changed hardware brightness or software dimming; unsupported displays are not shown as controllable; reconnecting does not apply a stale setting to a different monitor.

### BD-03. Extra dimming below normal minimum

**Description:** Dim a display below its minimum hardware brightness through a software overlay/color transform when supported.

**Build instructions:** reuse the existing dimming feature if present. Mark this as software dimming and avoid a full-screen always-on animation. Ensure the overlay is removed after app failure, switching display modes, display sleep and quit.

**Acceptance criteria:** dimming can always be reset using a documented recovery action; color transforms do not remain applied after disabling the feature.

### BD-04. Resolution and display mode selector — requested priority

**Description:** Enumerate supported display modes and allow changing resolution from Settings/menu bar.

**Build instructions:**

- Enumerate modes available from the operating system and filter out modes the OS reports as unusable for GUI use.
- Show a readable label such as `2560 × 1440`; optionally show logical (“looks like”) resolution in a separate field.
- Use a clear apply flow and retain a way back to the prior mode if the new mode produces a blank/unsupported display.
- Offer native/default and custom modes only when the current display stack can set them reliably. Do not invent mode IDs.
- Keep a per-display “revert if not confirmed” safeguard for risky mode changes. If a confirmation timer is impractical, provide a reliable keyboard/menu-bar recovery path before adding mode writes.

**Acceptance criteria:** switching to a listed valid mode changes the active mode and the readback reflects the selected mode; unsupported modes cannot be selected; hot-plug and sleep/wake do not corrupt the saved selection.

### BD-05. Refresh-rate selector — requested priority

**Description:** Switch among available refresh rates (for example 60/120 Hz) for each display, where the OS/monitor exposes those modes.

**Build instructions:**

- Derive selectable refresh rates from real available display modes, including variable refresh rate (VRR) metadata only if the source is understood.
- Deduplicate rates with appropriate display rounding but retain the actual mode identifier for selection.
- Do not promise a specific rate if the active connection/dock/cable has restricted the available modes.

**Acceptance criteria:** the selector lists only valid current modes and verifies the selected mode after applying it.

### BD-06. HiDPI / scaling controls — requested priority

**Description:** Select UI scaling choices separately from physical output resolution, making it clear how sharpness, UI size, and effective workspace change.

**Build instructions:**

- Start by listing system-supported scaling/HiDPI modes. Separate this from raw refresh rate and physical resolution in both the data model and UI.
- Use documented APIs where possible. Some flexible HiDPI/custom-scaled modes may require private or undocumented macOS mechanisms. Before implementation, document the exact API/approach, OS support, SIP/permission requirements, and recovery behavior.
- Do not write opaque display preferences, install system extensions or modify EDID/system files without an explicit design review and rollback plan.
- If the fully flexible path cannot be done safely with the current OS, implement the available supported scaling choices and record the remaining gap instead of silently claiming BetterDisplay parity.

**Acceptance criteria:** UI explains effective scaling, applies only validated modes, and offers a recovery path for unreadable/oversized modes.

### BD-07. Visual multi-display arrangement — requested priority

**Description:** Show a canvas with display rectangles that can be dragged into relative positions. Support identifying the active display and restoring a saved arrangement.

**Build instructions:**

- Reuse the existing display configuration mechanisms if available. Use system-supported display configuration APIs and validate before applying a complete layout.
- Represent coordinates in a documented coordinate system and handle mixed-DPI, portrait, different-sized and notched displays.
- Provide a visible main-display indicator and “Identify displays” overlay.
- Add grid snapping as a visual aid, but do not force inaccurate physical alignment when display sizes/scales differ.
- Preserve saved arrangements as user-created profiles, resolved against stable display identities at apply time.

**Acceptance criteria:** arrangement survives app restart and display reordering; unsupported/removed displays are skipped with an explanation; failed changes preserve or restore the prior layout.

### BD-08. Layout/configuration protection and profiles

**Description:** Store display setup profiles: layout, mode, refresh rate, rotation, scale and color profile when those settings can be captured/restored reliably. Auto-reapply a selected profile after an external monitor reconnects.

**Build instructions:**

- Build on BD-01 through BD-07; do not implement profile persistence before current layout/mode application is reliable.
- Add named profiles (e.g. desk, travel, presentation) and an optional per-monitor rule.
- Avoid infinite restore loops: coalesce display-change notifications, compare current configuration to target, retry only a limited number of times, and record failure.
- A profile that includes an unsupported setting must still apply its supported settings and report which setting was skipped.

**Acceptance criteria:** repeated profile activation is idempotent; reconnect loops terminate; unknown/renamed displays don't receive a profile meant for another display.

### BD-09. Favorite resolutions and keyboard shortcuts

**Description:** Save favorite modes per display and define global or per-display hotkeys for brightness, mode/profile changes and rotation, where allowed.

**Build instructions:** use existing shortcut management; do not add a second global hotkey system. Check conflicts with current Vorssaint shortcuts and macOS defaults. Revalidate the display/mode at trigger time.

**Acceptance criteria:** shortcuts do nothing destructive if the target display is absent; preferences backup and restore correctly.

### BD-10. Display groups and synchronized controls

**Description:** Group selected displays and synchronize brightness, software image controls and UI scale when comparable controls are supported.

**Build instructions:**

- Define a group as a set of stable display identities.
- Synchronize only a shared capability. Do not send hardware brightness values to a display with only software dimming without telling the user.
- If “match perceived brightness” is offered, treat it as a calibrated/estimated normalization and show its limitations; do not imply every display reports nits accurately.
- Avoid feedback loops where changing one display triggers synchronization recursively.

**Acceptance criteria:** individual override, group disable and hot-plug behavior are predictable; failure on one display does not block other group members.

### BD-11. Connection/disconnection management

**Description:** Switch between display setups, disconnect/reconnect external displays through supported interfaces, and optionally disable the internal panel when an external display is connected on compatible Apple Silicon Macs.

**Build instructions:**

- First implement profiles using normal OS configuration.
- Treat physical display disconnection and logical disable as different actions.
- Do not expose disconnect controls unless the OS API can recover after accidental disconnection. Offer a keyboard/timeout restore mechanism.
- Add automatic rules only after manual actions are reliable and can be disabled globally.

**Acceptance criteria:** the user can restore the prior display after accidental disconnect; automatic rules are not run repeatedly on every unrelated display notification.

### BD-12. Virtual displays and headless modes — advanced / later

**Description:** Create/associate virtual displays with configurable dimensions/aspect ratios, including a persistent desktop for remote/headless workflows where supported.

**Build instructions:**

- Treat this as a separate researched project, not a small extension to BD-04.
- Check current OS support, driver/system-extension/signing implications, session/login behavior, performance and display-capture restrictions.
- Never install a driver or system extension silently. Document setup, removal and recovery.
- Start with a prototype behind an experimental feature flag and test remote desktop, login window, sleep/wake, multiple profiles and removal.

**Acceptance criteria:** virtual screen can be created, queried, destroyed and recovered after crash without leaving a broken display configuration or orphaned service.

### BD-13. DDC/CI hardware controls

**Description:** For compatible monitors, expose brightness, contrast, input switching, volume, color-channel gain and power controls supported by the monitor.

**Build instructions:**

- Discover capabilities from the actual monitor before showing a control.
- Keep a model/transport capability cache and invalidate it on reconnection/firmware change.
- Prefer a well-maintained, properly licensed protocol implementation; check all dependency licenses before adopting one.
- Some Mac/monitor/port combinations may require non-public interfaces. Clearly isolate and document any such path, keep it optional, and do not pretend it is a stable public API.

**Acceptance criteria:** only supported controls appear; failure to communicate returns quickly and does not block the UI; a long DDC operation cannot stall sensor updates.

### BD-14. HDMI-CEC and external device integrations — advanced / optional

**Description:** On compatible HDMI paths, control TV volume/mute/power/input; optionally support documented integrations for supported smart TVs and AV receivers.

**Build instructions:**

- Do this only after explicit user opt-in and device capability discovery.
- Use documented local protocols/APIs. Never scan arbitrary local networks without consent.
- Store credentials/tokens in Keychain if an integration requires them; never log secrets.
- Each vendor integration is a separately disableable adapter with a clear compatibility matrix.

**Acceptance criteria:** no network discovery or device commands occur when the integration is disabled; unsupported devices are not presented as controllable.

### BD-15. HDR/XDR brightness and presets

**Description:** Expose the system's supported HDR/XDR brightness, SDR/HDR color modes and Apple display presets where available.

**Build instructions:**

- Start with passive capability/readout and normal system controls. Add writes only after testing on a supported panel and OS version.
- Distinguish built-in XDR displays from external HDR displays; their controls and capabilities differ.
- Never claim a panel is producing a given nit level unless the source actually supports that measurement.
- Any brightness beyond the normal system range must be gated by display/OS support and have clear temperature/comfort warnings where relevant.

**Acceptance criteria:** no HDR-specific controls on unsupported displays; values are verified after changes; ordinary brightness still works if the extra-brightness feature is unavailable.

### BD-16. Color profiles, RGB/YCbCr modes and color controls

**Description:** List/select installed color profiles and supported display output modes; optional software color temperature, hue/saturation, geometry, sharpening and other image adjustments.

**Build instructions:**

- Implement profile selection via supported system mechanisms first.
- Treat custom color transforms as software output processing, not panel calibration. Add reset-to-default and per-display state.
- Only expose RGB/YCbCr, chroma subsampling, HDMI range and extra color modes if the display/connection stack reports those options.
- Forced HDR switching, automatic SDR/HDR preset switching and advanced compositor filters may require private APIs or unsupported access; evaluate separately and feature-gate accordingly.

**Acceptance criteria:** every transform can be reset; mode writes are supported by the active display; normal UI remains responsive during transitions.

### BD-17. Custom 3D LUTs

**Description:** Import a 3D LUT and apply it to supported display adjustment or video preview/streaming paths.

**Build instructions:**

- Treat LUT support as advanced. Define a supported file format and validate size, encoding and bounds at import.
- Apply only to the rendering path actually controlled by Vorssaint; do not state it calibrates all system output unless it truly does.
- Support preview, reset, profile save/restore and safe handling of malformed/large files.

**Acceptance criteria:** malformed LUTs are rejected without crashing; disabling a LUT restores unmodified rendering.

### BD-18. Picture-in-picture, display streaming and selected-window streaming

**Description:** Show a display, a virtual display, a selected window or a group of windows in a movable picture-in-picture window; optionally stream/crop/rotate/flip it, target a frame rate, or create teleprompter/portrait workflows.

**Build instructions:**

- Reuse the existing screen capture/recording permission and framework patterns where possible.
- Require explicit screen-recording permission and start capture only after user action. Stop streams when the window closes, the feature is disabled or access is revoked.
- Put frame rate/resolution bounds on streams; do not run a continuous full-screen capture just because the module is enabled.
- Clearly distinguish a local preview/stream window from creating a real virtual display.
- Crop, rotate, mirror and teleprompter effects should be composable, but avoid overengineering before the basic low-rate PIP works.

**Acceptance criteria:** permission denial is safe; streams stop on close/disable; CPU/GPU/memory usage is measured at each configured frame rate; no images are saved or uploaded unless the user requests it.

### BD-19. Display OSD and menu-bar UX

**Description:** Optional on-screen feedback for brightness/volume changes, menu-bar sliders, quick settings, and an optional sidebar-style control panel.

**Build instructions:**

- Use Vorssaint's visual design system and localization pipeline. Do not copy BetterDisplay artwork/branding/UI source.
- OSD should be brief, non-interfering and dismissable; support traditional/native and custom presentation only if both can be maintained.
- Reuse global shortcut infrastructure. Changes must not conflict with existing mouse/keyboard utilities.

**Acceptance criteria:** OSD can be disabled; it does not capture input or remain above full-screen applications unexpectedly; menu controls remain keyboard-accessible.

### BD-20. Display events, automation, CLI and Shortcuts

**Description:** Run user-configured actions when a display connects/disconnects or the Mac sleeps/wakes; expose profile/mode/brightness actions to Shortcuts and optionally a local CLI/API.

**Build instructions:**

- Build event triggers on BD-08's profiles and the existing scheduler/Shortcuts framework where possible.
- Do not create a network listening server by default. Any HTTP integration must be disabled unless explicitly enabled and bound to loopback/authenticated.
- Prefer App Intents for user-visible macOS Shortcuts actions. A local CLI should invoke the same typed service API, not duplicate logic.
- A display event must not trigger a destructive mode repeatedly. Add debounce, loop prevention and local execution logs.

**Acceptance criteria:** all actions are idempotent or have explicit duplicate-run protection; no automation runs while disabled; failures are visible in local logs.

### BD-21. Display diagnostics and console

**Description:** A copyable diagnostics panel for mode list, EDID/DPCD/DSC information, connection/bandwidth/compression/tiling where available, support flags, and recent action logs.

**Build instructions:**

- Distinguish OS-exposed values from inferred or unavailable values.
- Redact local identifiers and private network data from any “share diagnostics” operation by default, with a preview before copying.
- Do not build an always-on log collector. Use bounded local logs with retention.

**Acceptance criteria:** diagnostics never crash if a field is absent; all reported capabilities have a known source; exported reports do not contain credentials.

### BD-22. Localization

**Description:** Ensure all newly added display settings, errors, diagnostics and accessibility labels follow Vorssaint's language support.

**Build instructions:**

- Update every locale in the repository's `AppLanguage.allCases` and any feature-specific string catalogs, following current project guidance.
- Test long labels, unit formatting, decimal separators, display names and right-to-left layouts if supported by the existing UI.

**Acceptance criteria:** no new user-visible hard-coded strings outside established exceptions; all locale coverage checks pass.

---

## 5. AlDente-style battery care — complete requested feature set

**Safety rule for every item in this section:** the user-interface target is not equivalent to hardware state. Every state-changing operation must go through the battery controller, use a supported capability adapter, be verified from readback/telemetry, and expose an error when verification fails.

### BAT-01. Charge Limiter

**Description:** Select a charge target (integer percentage, normally 20–100%) using a slider or editable field. If below the target, charge to the target and hold; if above it, stop charging but do not actively discharge unless a discharge mode is explicitly enabled.

**Build instructions:**

- Store the user's preferred limit separately from temporary overrides.
- Validate range, reject NaN/out-of-range input, debounce field editing, and show the applied limit separately from the preferred limit if the hardware API quantizes it.
- Define behavior for low battery, no external power, sleep, and unavailable control support.
- Read back the charge state after applying. Show `Enforcement active`, `Target pending`, `Read-only`, or `Failed` states instead of a simplistic on/off label.

**Acceptance criteria:** setting a value updates the UI and desired state; supported hardware readback confirms enforcement; restart restores desired preferences and reconciles the current device state.

### BAT-02. Top Up (temporary 100% override)

**Description:** Temporarily raise the charge target to 100% for a one-off need, then return to the user's prior target when the session ends, especially on charger disconnect.

**Build instructions:**

- Snapshot the prior target before enabling Top Up; persist a marker for the active override so an app restart cannot accidentally lose the original target.
- While active, set the effective target to 100% through the normal battery controller.
- Revert on AC disconnect per the product rule, and also handle app restart, power-source notifications arriving out of order, and user manually changing the saved target during Top Up.
- Keep Heat Protection active. Show an explicit active badge/countdown/state, not just an icon.

**Acceptance criteria:** prior target is restored exactly once; repeated disconnect events are idempotent; Top Up cannot overwrite the user's saved baseline.

### BAT-03. Hardware Battery Percentage

**Description:** Show macOS's reported battery percentage and, when a verified hardware/battery-management-system value is available, a separate hardware percentage.

**Build instructions:**

- Display both values as different sources, not conflicting versions of one field.
- Use macOS's reported percentage for control decisions unless research and real-hardware tests justify a different policy; hardware percentage is informational by default.
- If the raw value cannot be read, display `--` and keep other battery features working.

**Acceptance criteria:** unavailable hardware percentage never blocks charge limiting; labels and source are explicit; no value is fabricated by simply deriving a decimal from macOS's rounded integer.

### BAT-04. Live Status Icons

**Description:** Show menu-bar state for plugged-in-and-charging, plugged-in-and-holding, plugged-in-and-discharging, and unplugged/on-battery.

**Build instructions:**

- Derive the state from the canonical battery state machine and current power-source snapshot.
- Use native SF Symbols/system-consistent imagery. Provide textual accessibility labels and status in the popover.
- Keep state transitions debounced enough to avoid flicker but do not hide real state changes for several seconds.

**Acceptance criteria:** unplugging and plugging in updates the icon; each icon has an accurate accessibility label; UI state cannot contradict the service's verified state.

### BAT-05. Disable Sleep Until Charge Limit

**Description:** While plugged in and charging toward the target, optionally delay system sleep until the target is reached; re-enable sleep when the target is reached or the adapter is unplugged.

**Build instructions:**

- **High-risk, opt-in feature.** Keeping a closed MacBook awake may cause heat buildup or unexpected behavior. Do not enable by default.
- Investigate actual macOS behavior and whether available assertions can accomplish the desired lid-closed behavior on supported models; do not assume `IOPMAssertion` overrides forced clamshell sleep.
- If a privileged setting or `pmset` behavior is used, follow the repository's existing permission/authorization process and limit authorization to the exact setting required. Never silently disable system sleep globally.
- Keep display off when appropriate. Monitor unplugging, limit reached, helper failure, app termination and system shutdown. Unconditionally release any sleep assertion on disconnect/error.
- If lid-closed operation cannot be reliably supported, implement a transparent “keep awake while charging, lid open” mode or mark the clamshell mode unsupported rather than promising it works.

**Acceptance criteria:** tests verify every exit path releases the sleep prevention; the UI describes the exact supported scenario; no indefinite keep-awake assertion survives a failure.

### BAT-06. Stop Charging When Sleeping

**Description:** Before system sleep, capture the current macOS battery percentage and pause charging so the machine does not continue charging beyond that point while asleep, where the hardware behavior allows it.

**Build instructions:**

- Inspect current sleep notification/IOKit integration and use the earliest reliable sleep-transition event available. `NSWorkspace.willSleepNotification` alone may not provide enough time on every path; prove the timing on physical hardware.
- Persist the intended pause state before sleep and reconcile it on wake.
- This feature is about maintaining the current value at sleep transition, not forcing the active configured limit after wake.
- Make clear that sleep/shutdown control differs between Mac models and firmware. Do not claim universal persistence without tests.

**Acceptance criteria:** supported hardware remains paused across a sleep/wake test; unsupported cases are documented; wake reliably restores the normal charge policy without oscillation.

### BAT-07. Stop Charging When App Closed

**Description:** Keep the charge-control state active after the main UI app quits on supported Apple Silicon hardware.

**Build instructions:**

- First determine if the hardware retains the necessary state by itself. If not, use the narrowly scoped helper described in Section 2.5.
- Separate “close window,” “quit UI,” “log out,” “switch user,” “restart helper” and “power off” semantics. Do not promise persistence across shutdown unless verified.
- Expose helper registration/health and let the user disable it. If macOS disables the service, report that charge protection may no longer persist.
- On helper or app startup, reconcile stored target with actual hardware state.

**Acceptance criteria:** when supported and enabled, quitting the UI does not reset the active hold; when the helper is disabled/uninstalled the behavior is clearly reported; app quit never leaves an undocumented state.

### BAT-08. Discharge

**Description:** While plugged in, optionally use battery power until the configured target is reached, then return to normal adapter-powered holding/charging.

**Build instructions:**

- Treat this as a high-risk hardware operation because it can require simulating/disabling adapter charging through a low-level interface.
- Validate that the target is below the current charge level before starting. Require a clear user action and display that battery level will fall while plugged in.
- Use a maximum time/low-charge guard; stop if the adapter is disconnected, battery telemetry is stale, battery falls below the configured safety margin, thermal protection triggers, or verification fails.
- Define explicit stop/cancel behavior. Restoring normal charging control must be guaranteed, not best-effort without feedback.
- Test with sleep/clamshell closed only as a separately controlled compatibility case; never imply ordinary power assertions automatically make this safe.

**Acceptance criteria:** discharge starts only on eligible hardware and valid targets; ends at the target or a safety stop; adapter reconnection and app crash recover safely; status comes from actual battery/power telemetry.

### BAT-09. Automatic Discharge

**Description:** When the target is below current charge while plugged in, automatically start the verified Discharge operation until the target is reached.

**Build instructions:**

- Build only after BAT-08 has passed physical-device tests.
- Use an explicit state machine so lowering a target cannot repeatedly start parallel discharge tasks.
- Pause while Calibration Mode, Top Up, sleep transitions or a higher-priority safety guard is active; define these interactions in user-facing docs.
- Provide a master on/off toggle, status explanation, and immediate stop action.

**Acceptance criteria:** changing the target below current charge results in at most one active discharge operation; raising the target cancels a running discharge safely; disable/restart reconciles the state without duplicate operation.

### BAT-10. Sailing Mode (hysteresis interval)

**Description:** Avoid frequent charge-state changes by charging to an upper threshold, then pausing until the battery falls to a lower threshold before recharging.

**Build instructions:**

- Model this as two thresholds, not as active discharge. Example: upper limit 80%, lower limit 75%.
- Validate `0 <= lower < upper <= 100`. Clarify the interaction with the primary charge limit and do not implement the behavior as “actively discharge from 80% to 75%” unless Discharge is separately enabled.
- Derive transition decisions from macOS percentage and confirmed charging state; use hysteresis to avoid toggling due to rounding/noisy readings.

**Acceptance criteria:** no rapid on/off oscillation around one percentage point; no active battery discharge is initiated by Sailing Mode alone; saved values validate and restore.

### BAT-11. Heat Protection

**Description:** Pause charging when battery temperature exceeds a configurable threshold; resume according to a hysteresis/cool-down policy.

**Build instructions:**

- Reuse the shared temperature sensor service and identify a verified battery-temperature sensor, not the hottest CPU/GPU sensor.
- Set a configurable threshold and default based on researched guidance, with clear warning that this is a policy choice, not a diagnostic.
- Use temporal hysteresis: require a sustained over-threshold condition before pause; after cooling, wait the configured recovery interval and re-check to avoid rapid toggling.
- Do not suspend Heat Protection during Calibration Mode or Top Up. All other modes must respect it.
- If the battery temperature reading becomes unavailable/stale, never use an invented value; report “protection telemetry unavailable” and follow a documented conservative policy.

**Acceptance criteria:** tests cover threshold crossing, missing readings, stale data, exact hysteresis timing, Top Up and schedule conflicts; the charging state returns only after the recovery rule is satisfied.

### BAT-12. Control MagSafe LED

**Description:** Where hardware supports it, use the MagSafe LED to indicate charging/holding/discharging state (green/orange/blinking/off).

**Build instructions:**

- Treat this as model-specific and advanced. Verify exact supported MacBook/MagSafe versions and a safe write/read path before implementation.
- Do not invent SMC keys or write unknown values to the controller. If no reliable supported path exists, keep feature off and list it as unsupported.
- Separate “LED behavior” from charging state. If LED write fails, battery management continues and a message explains the fallback.
- Support user preference to disable LED changes, and restore default hardware-controlled behavior during uninstall if possible.

**Acceptance criteria:** no LED-control command runs on unsupported hardware; all modes are tested on each listed model; failures do not affect charging control.

### BAT-13. Fast User Switching

**Description:** Keep one consistent charge policy when switching between macOS accounts.

**Build instructions:**

- Do not assume a per-user UI app stays alive during Fast User Switching. Coordinate through the helper/OS-persistent state only if the helper architecture is already justified.
- Define whether settings are device-wide or user-specific. For battery safety, the effective controller policy should have an explicit priority rule when multiple users have different preferred limits.
- On login/user activation, detect current service status and reconcile once. Avoid charging toggles during transition.

**Acceptance criteria:** tests cover same limits, conflicting limits, one user with Vorssaint closed, missing permissions, user logout and helper disabled.

### BAT-14. Calibration Mode

**Description:** A guided optional battery-percentage calibration cycle with configurable stages similar to charge to 100%, discharge to 10%, charge to 100%, hold, then restore the preferred limit.

**Build instructions:**

- Treat this as an expert, opt-in sequence, not an automatic battery-health optimization. Modern battery systems vary; don't promise that calibration extends battery life.
- Build as a persisted finite-state machine with stages, completion/failure states, resume after restart and a user-visible cancel button.
- Before starting, confirm the adapter is connected, battery telemetry is fresh, target/settings are available, and the user accepts the long-running cycle.
- Retain Heat Protection. Never bypass thermal safeguards to speed up calibration.
- Avoid deliberately draining to 0%; use the documented conservative target (the requested plan mentions 10%) and stop if safety limits or unexpected power loss occur.
- Always restore the saved charge policy on completion, cancellation, hardware error or app restart.

**Acceptance criteria:** each transition has tests; app quit/restart resumes or safely cancels; safety interruption preserves the previous preference and records a reason; completion is not declared until telemetry confirms the final state.

### BAT-15. Scheduler

**Description:** Schedule battery actions with one-time/daily/weekday/weekly/biweekly/monthly repeat options, active/inactive state, execution history and catch-up for missed tasks.

**Supported actions:** set charge limit, Top Up, pause charging, start/stop discharge, start Calibration Mode, toggle Low Power Mode and other actions explicitly added to the allowed action registry.

**Build instructions:**

- Use a typed action enum and validated parameters. Do not store executable command strings or permit arbitrary scripting inside the scheduler.
- Store local wall-clock intent plus timezone/repeat rule carefully; define daylight-saving behavior, timezone changes, duplicate-run prevention and clock changes.
- macOS does not guarantee arbitrary code runs at an exact time while a Mac sleeps. Catch-up means “run on next eligible wake/login,” not “the task always ran at scheduled time.” Show missed/late actions clearly.
- Make execution idempotent where possible, write a bounded local history and prevent unsafe tasks from starting without current telemetry/power context.

**Acceptance criteria:** tests cover DST gaps/folds, timezone change, sleep/wake, app/helper restart, duplicate events, invalid actions, and catch-up settings.

### BAT-16. Automatic Scheduled Calibration

**Description:** A convenience template in the scheduler that runs Calibration Mode on a selected recurring schedule.

**Build instructions:**

- Implement as a scheduler template/action, not a second timer subsystem.
- Do not schedule by default. Ask the user to confirm start time and expected long-running cycle.
- If the Mac is asleep or off at the scheduled time, use the catch-up setting and show the actual start time.

**Acceptance criteria:** exactly one calibration instance can run; overlapping schedules are rejected or queued according to explicit rules.

### BAT-17. Power Flow Sankey diagram

**Description:** Visualize the energy path among external adapter, battery and system power consumption.

**Build instructions:**

- Reuse available power telemetry and the shared sampling service.
- Build a model with each data point tagged as `measured`, `derived`, or `estimated`. Not every model exposes adapter input watts, system consumption watts and battery charge watts independently; do not invent exact splits.
- If only part of the flow is available, draw the known flows and label the remainder as estimated/unknown rather than forcing a false sum.
- Animate only when the panel is visible; cap update rate and use lightweight native drawing. Keep the menu-bar popover version compact.

**Acceptance criteria:** energy values have units/provenance; values do not go negative due to counter noise; UI stops animating and sampling more frequently when hidden.

### BAT-18. Apple Shortcuts / App Intents integration

**Description:** Expose battery actions and queries to macOS Shortcuts and, where appropriate, Siri/App Intents.

**Minimum actions/queries:** get battery status; get macOS and hardware percentage; get temperature; set charge limit; pause/resume charging; Top Up; start/stop discharge; get current controller state; start/cancel calibration; set MagSafe LED only on supported models; query schedule status.

**Build instructions:**

- Use Apple's App Intents framework where supported by the existing target and OS.
- Every intent calls the same typed service API as the UI. Do not duplicate battery control logic in intent handlers.
- Validate inputs again in the service layer. Return human-readable status/error results.
- For actions that are long-running or dangerous, require an explicit confirmation or return current state and request a separate start command.

**Acceptance criteria:** actions show up in Shortcuts; tests cover invalid percentages, unsupported hardware, helper denial, missing telemetry and attempts to start a duplicate calibration.

### BAT-19. Pause Charging and quick battery actions

**Description:** Set the effective limit to the current macOS percentage to pause charging without changing the saved preferred limit, then expose a quick control to resume the normal policy.

**Build instructions:**

- Keep “pause at current percentage” distinct from “disable the limiter.”
- Persist whether pause is a temporary state; define how it behaves after unplug, restart, user switch and Top Up.
- Add these actions to the quick panel/menu-bar UI and Shortcuts using the shared controller.

**Acceptance criteria:** a temporary pause does not lose the saved preferred limit; Resume restores the user's policy exactly once.

### BAT-20. Battery/power specification panel and popover customization

**Description:** Present battery telemetry (capacity, cycle count, temperature, adapter/power, percentages and supported health fields) in a customizable battery panel and let users select compact menu-bar data/icons.

**Build instructions:**

- Reuse ST-08 telemetry and the existing panel/layout framework.
- Let the user choose visible fields, compact/expanded layouts and icon style; persist settings through the current backup system.
- Keep the battery UI responsive when hardware telemetry is unavailable.

**Acceptance criteria:** customization restores after backup/import; unavailable fields are hidden or labelled appropriately; the panel does not add its own sensor polling.

### BAT-21. Discharge in clamshell mode — compatibility extension

**Description:** Where verified, allow discharge while connected to an external display with the lid closed.

**Build instructions:**

- Treat clamshell discharge as a separate capability from basic discharge and from “Disable Sleep until Charge Limit.”
- Requires model/OS-specific thermal, sleep and power testing. Do not assume keeping the Mac awake with the lid shut is safe.
- Keep experimental and disabled by default until there is a documented and repeatable test matrix. If unsupported, block the action with an explanation.

**Acceptance criteria:** supported/unsupported combinations are listed; all failure/unplug/overheat/cancel paths return sleep and charge control to the documented normal state.

---

## 6. Integration and conflict requirements

### 6.1 Single source of truth

All interfaces must reflect the same service state:

- Menu-bar icon and popover
- System monitor and battery panel
- Settings controls
- Scheduler and action history
- App Intents/Shortcuts
- Optional command-line interface

No feature may maintain a separate hidden “truth” about charge status, display configuration, sensor readings or whether its helper is active.

### 6.2 Conflict matrix

The agent must implement and unit-test an explicit matrix for these overlaps:

| Situation | Required behavior |
|---|---|
| Top Up + charge limit | Top Up temporarily wins; original preferred limit remains saved and is restored on completion/unplug policy. |
| Top Up + Heat Protection | Heat Protection wins and pauses charging as required. |
| Discharge + Automatic Discharge | Only one discharge operation can exist. |
| Discharge + Calibration | Calibration owns the battery state machine; manual/automatic discharge is paused/cancelled according to documented stage rules. |
| Calibration + Heat Protection | Heat Protection remains active. |
| Stop Charging when Sleeping + Disable Sleep until Limit | Define precedence explicitly; never both pause charging and prevent sleep indefinitely without informing the user. |
| Scheduling + active manual action | Do not silently override a currently running safety-sensitive action. Queue/reject/replace according to a visible rule. |
| Different macOS user accounts | Apply the documented device-wide policy; never create two hardware controllers. |
| Display profile + manual display change | Manual changes should not cause an infinite profile reapply loop. |
| Display hot-plug + scheduled profile | Coalesce duplicate events and apply at most once per stable configuration. |
| Sensor stale/unavailable + alert or Heat Protection | Mark telemetry unavailable; follow a documented fail-safe policy and never treat missing values as safe values. |

### 6.3 Privacy and permissions

- Follow existing Vorssaint permission gating and explain why a permission is needed before asking.
- Battery control should not require network access.
- Display control and telemetry should remain local unless the user explicitly uses an existing external integration.
- No new telemetry/analytics upload.
- Any local HTTP endpoint, external CLI, device discovery or streaming capability must be opt-in, bounded and documented.
- Do not include personal identifiers, serial numbers, network names, filenames or secrets in default log exports.

---

## 7. Delivery phases and ordering

Do not ask the maintainer to accept a huge all-at-once patch. Land and test one vertical slice at a time.

### Phase 0 — Audit and benchmark (no product behavior changes)

1. Map existing code to the feature list.
2. Record current optimized/developer build results, self-test results and existing test suites.
3. Capture a repeatable resource baseline: Vorssaint idle; Vorssaint with current monitor visible; Stats running by itself; BetterDisplay running by itself; AlDente running by itself; all three separately; all three together; and Vorssaint with equivalent features enabled.
4. Record macOS version, Mac model/chip/RAM, attached displays, power mode and exact feature/polling settings.
5. Create `docs/unified-utility-implementation-status.md` with a table of implemented/partial/missing/unsupported capabilities and evidence.

### Phase 1 — Shared monitoring parity

Implement/verify ST-02, ST-03, ST-04 and ST-12 first: hottest CPU/GPU sensor, details, compact menu-bar display and bounded graph. Reuse the existing monitor/sensor service. Extend battery/power telemetry using ST-08 only after confirming existing coverage. Add relevant tests and translations.

### Phase 2 — Basic display controls

Implement/verify BD-01, BD-02, BD-04, BD-05, BD-06 and BD-07. Prioritize: detect displays correctly, list supported modes, change resolution/refresh where supported, present current scaling information and manage a basic arrangement. Provide a recovery path for mode/layout failures before releasing controls.

### Phase 3 — Battery read-only model and safety state machine

Implement ST-08/BAT-03/BAT-04/BAT-20 read-only. Build the typed battery state machine and mock adapter. Validate all transitions in unit tests before enabling any hardware write.

### Phase 4 — First hardware write: Charge Limiter

Implement BAT-01 for one explicitly supported hardware configuration, then test readback, sleep/wake, restart, OS updates, error recovery and battery-controller teardown. Keep unsupported devices read-only. Do not implement all other battery actions until this passes.

### Phase 5 — Low-risk battery actions

Implement BAT-02 Top Up; BAT-10 Sailing Mode (without active discharge); BAT-11 Heat Protection; BAT-19 Pause Charging; BAT-18 Shortcuts read-only/query and set-limit actions. Add status icons and conflict tests.

### Phase 6 — Persistence and sleep behavior

Research and implement BAT-06 Stop Charging when Sleeping, BAT-07 Stop Charging When App Closed, BAT-13 Fast User Switching and BAT-05 Disable Sleep Until Limit only if the required model/OS behavior is verified. Add helper only if necessary. Do not bundle these into a generic root script.

### Phase 7 — Discharge and calibration

Implement BAT-08 Discharge in a narrow supported hardware matrix, then BAT-09 Automatic Discharge, BAT-14 Calibration Mode, BAT-15 Scheduler, BAT-16 Scheduled Calibration and BAT-21 clamshell discharge. Each stage must have dedicated physical-device test evidence before proceeding to the next.

### Phase 8 — Advanced display controls

Implement BD-08 profiles; BD-09 shortcuts; BD-10 groups; BD-11 connection management; BD-13 DDC controls; BD-15/BD-16 supported HDR/color controls; BD-19 OSD; BD-20 automation; BD-21 diagnostics. Keep unsupported/private mechanisms isolated and optional.

### Phase 9 — High-risk/large-scope display work

Only after core app performance remains acceptable, evaluate BD-12 virtual displays, BD-17 3D LUTs, BD-18 selected-window/display streaming, and BD-14 HDMI-CEC/smart-device integrations. Build prototypes behind independent feature flags and evaluate CPU/GPU/RAM cost before broad integration.

### Phase 10 — Final parity and resource decision

Repeat the baseline workload with equivalent visible features and comparable polling intervals. Document all missing/experimental features, licensing boundaries, hardware support and benchmark data. Do not claim Vorssaint is lighter or fully replaces the three products unless measured evidence supports that claim.

---

## 8. Performance and memory budget

### 8.1 Baseline methodology

Compare the following workloads on the same Mac, macOS release, power source and attached-display setup:

1. Each original app alone with the intended modules enabled.
2. The three apps simultaneously with equivalent monitoring/display/battery features active.
3. Vorssaint alone with corresponding features enabled.
4. Vorssaint with those modules disabled to measure the idle baseline.
5. Vorssaint with the system monitor visible versus hidden.
6. Optional features that capture/stream screen content, drive DDC devices or run background automation, individually and in combinations.

For each run, allow startup/warm-up, record at least several minutes of idle behavior and a repeatable active workload, and run multiple trials. Capture the app and helper processes separately; a single app RSS number is not sufficient if a helper is running.

Suggested tools: Activity Monitor, Instruments (Allocations/Time Profiler/Energy Log where available), and built-in process/system measurements. Record exact commands/tools and repeatability in the report. Do not use a benchmark measured on a simulator as evidence for temperature, battery, display or helper behavior.

### 8.2 Engineering goals

These are initial regression targets, to be measured and adjusted from the actual baseline rather than treated as guarantees:

- Disabled optional features add no continuous feature-specific polling or listeners.
- Shared monitoring uses one collector per data family, not one per UI view.
- Hidden panels stop animation and reduce sampling where safe.
- No repeating subprocess launch for routine sensor/battery/display polling.
- No continuously running screen capture or virtual-display pipeline unless actively requested.
- No new helper process unless persistence/privilege requirements justify it.
- The app remains responsive during slow monitor/SMC/DDC operations; device operations are asynchronous and have timeouts.
- No runaway memory growth after an overnight/all-day soak test.
- Quiescent average CPU and energy impact should remain close to the pre-change app baseline; report measured differences instead of claiming an arbitrary win.

### 8.3 Required benchmark report

Record at least:

| Measurement | Record |
|---|---|
| Machine | Model/chip, RAM, battery condition where known |
| OS | Exact macOS version/build |
| Build | Commit SHA, build variant, architecture, signing mode |
| Workload | Modules active, polling cadence, displays attached, power source |
| Memory | Per-process/helper memory and trend, not only a single snapshot |
| CPU | Average and spikes, sampler-related work if identifiable |
| Energy | Activity Monitor/Instruments observation over same interval |
| Responsiveness | Menu open latency, display switch latency, sensor update latency |
| Reliability | Errors, stale telemetry, wake/hot-plug behavior |
| Evidence gap | Anything that was not tested on real hardware |

The final decision is empirical: keep the unified implementation if the equivalent workload is functionally correct and its resource profile is acceptable. If a feature makes the app heavier than the standalone option and cannot be optimized without destabilizing it, make that feature independently disableable or leave it out.

---

## 9. Test plan and acceptance gates

### 9.1 Unit tests (required)

- Battery state transitions and precedence rules.
- Input validation for charge limits and Sailing Mode bounds.
- Top Up save/restore behavior across repeated events and app restart.
- Heat Protection hysteresis, stale/missing temperature, cooldown and mode conflicts.
- Discharge start/stop/cancel logic, low-battery stop and duplicate-operation prevention.
- Calibration-stage persistence, cancel/restart recovery, restore-preference behavior and permanent retention of thermal safety.
- Scheduler timezone/DST/duplicate/catch-up/disabled-task behavior.
- Display-mode parsing, scaling-vs-resolution labels, stable identity fallback and profile matching.
- Display hot-plug debouncing, partial profile apply and restore-failure paths.
- Telemetry staleness, unavailable samples, sensor classification and maximum temperature selection.
- Preferences backup/import and localization coverage.

Test services against fake hardware adapters. Unit tests must not write to real SMC keys, change actual display modes, keep the machine awake or start a real calibration cycle.

### 9.2 Hardware integration tests (required before declaring features supported)

On each claimed hardware/OS combination, verify:

- Charge limit below and above current charge, unplug/replug, restart and verified readback.
- Top Up restores the previous limit on the exact documented event.
- Sleep/wake while charging and after reaching the limit.
- App quit, helper quit/disable, Fast User Switching and login/logout as applicable.
- Heat Protection at controlled test thresholds with a valid battery-temperature sensor.
- Manual/automatic discharge cancellation, safety stop and return to normal charging.
- Calibration failure/cancel/restart and restored policy.
- Internal/external display mode changes, refresh rates, scaling and display arrangement.
- Hot-plug and sleep/wake with profiles enabled.
- Unsupported-device paths for any controls that are not universally available.

Do not heat a MacBook unsafely or artificially stress a battery for testing. Use controlled, conservative tests and stop if the device becomes unexpectedly hot or behaves abnormally.

### 9.3 Manual UX/security checklist

- Feature can be disabled and re-enabled without a full reinstall.
- Disabled feature has no ongoing polling, observer or helper work beyond what is essential.
- UI and Shortcuts report unsupported hardware and permissions failures clearly.
- No dangerous operation starts without explicit opt-in.
- Cancel is available for long-running operations.
- No action can request arbitrary root command execution.
- Helper disable/uninstall has a recovery path.
- No unknown/private hardware command is written to a device without an explicit, tested capability mapping.
- The feature behaves correctly when its panel is hidden, app launches into background, the system wakes, a monitor reconnects, or the app is force-quit.
- All user-visible text is localized following repository conventions.

### 9.4 “Done” means all of these

A feature is not done because the agent wrote the UI or because the project compiles. Mark it **Done** only when:

1. The implementation exists and is wired into the current feature catalog/services.
2. Unit tests pass for normal behavior and important failure cases.
3. The full app builds and self-tests pass.
4. The feature is exercised on real hardware if it changes hardware behavior or depends on a hardware-specific API.
5. Permissions, settings backup, localization, logging and removal behavior are handled.
6. The UI reports the actual confirmed state and gives understandable errors.
7. The documentation states supported macOS/hardware combinations and remaining limitations.
8. Performance impact has been measured if the feature introduces polling, screen capture, a helper, or display rendering.

---

## 10. Licensing, dependency and upstream boundaries

These projects are references, not permission to copy everything indiscriminately:

- **Vorssaint:** current repo describes itself as GPL-3.0-or-later, native Swift, modular and local-first. Follow the repository's current license and trademark/branding files.
- **Stats:** its repository identifies the source as MIT-licensed. If code is directly reused, preserve copyright and license notices and record what files/components were reused. Review transitive dependencies separately.
- **BetterDisplay:** its GitHub repository and documentation expose a mix of functionality and identify certain features as Pro/licensed. Do not assume the ability to view a public repository equals permission to transplant arbitrary code or reproduce a paid feature. Do not bypass licensing checks. Prefer a clean implementation using documented macOS APIs/protocols, or use documented integration only as an optional bridge during evaluation.
- **AlDente:** current Free/Pro implementations are proprietary; early AlDente Classic releases were open source, but that does not automatically permit copying current commercial feature implementations. Treat the feature descriptions as behavior requirements, not code to copy.
- Check and document license compatibility before introducing source code or third-party dependencies. Add required notices and attribution. Do not include third-party icons, screenshots, copy text, proprietary algorithms or branding without a valid license.

A documented BetterDisplay CLI integration can be useful as a **temporary comparison/bridge** while evaluating behavior, but it does not count as a full native replacement and should not be used to claim reduced combined RAM if BetterDisplay must remain running. The default final implementation should not require another utility app for the core requested features.

---

## 11. Feature completion tracker template

Keep this table in `docs/unified-utility-implementation-status.md` and update it in each implementation phase.

| ID | Feature | Priority | Status | Hardware/OS tested | Tests | Performance evidence | Known limitations |
|---|---|---:|---|---|---|---|---|
| ST-02 | Hottest CPU/GPU temperatures | P0 | Not assessed | — | — | — | — |
| BD-04 | Resolution selector | P0 | Not assessed | — | — | — | — |
| BD-05 | Refresh-rate selector | P0 | Not assessed | — | — | — | — |
| BD-06 | HiDPI/scaling controls | P0 | Not assessed | — | — | — | — |
| BD-07 | Display arrangement | P0 | Not assessed | — | — | — | — |
| BAT-01 | Charge limiter | P0 | Not assessed | — | — | — | — |
| BAT-02 | Top Up | P1 | Not assessed | — | — | — | — |
| BAT-11 | Heat Protection | P1 | Not assessed | — | — | — | — |
| BAT-18 | Shortcuts/App Intents | P1 | Not assessed | — | — | — | — |

Statuses must be one of: `Not assessed`, `Implemented`, `Partial`, `Experimental`, `Blocked`, `Unsupported`, `Done`. Include a commit reference or test evidence for `Done`.

---

## 12. Reference links checked while preparing this specification

Use these as starting points, not as a substitute for inspecting the current project and current documentation before coding:

- [Vorssaint repository](https://github.com/vorssaint/vorssaint-utils)
- [Vorssaint contribution guide](https://github.com/vorssaint/vorssaint-utils/blob/main/CONTRIBUTING.md)
- [Vorssaint agent-assisted contributions](https://github.com/vorssaint/vorssaint-utils/blob/main/docs/AI-CONTRIBUTIONS.md)
- [Stats repository and feature inventory](https://github.com/exelban/stats)
- [BetterDisplay repository and current feature overview](https://github.com/waydabber/BetterDisplay)
- [BetterDisplay license/feature boundary overview](https://betterdisplay.pro/guide/licensing/free-and-pro-features/)
- [AlDente official feature reference](https://apphousekitchen.com/aldente-overview/features/)
- [AlDente official overview](https://apphousekitchen.com/aldente-overview/)
- [Apple: Service Management / SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [Apple: Core Graphics display modes](https://developer.apple.com/documentation/coregraphics/cgdisplaymode)
- [Apple Support: Mac operating temperatures](https://support.apple.com/en-us/102336)

## Final instruction to the AI coding agent

Treat this document as a product roadmap and specification, not as permission to implement all features in one patch. First audit the repository and report what already exists. Then implement the highest-priority small slice. Build, test and benchmark it before moving on. Prefer accurate partial support over a broad set of controls that do not work reliably. Never claim a hardware operation succeeded without reading back the actual state, and never sacrifice charging, thermal, sleep or display recovery safety to reach feature parity.
