# Implementation Roadmap: Features to Build

Ordered from easiest to hardest to implement:

### 1. Charge Limiter
- **Description**: Choose the charge level your MacBook holds while plugged in. Drag slider or type percentage. Pauses charging at limit, runs on adapter power.
- **Details**: Basic target percentage setting and charge state control via SMC or system battery management flags.
- **Examples**: Setting limit to 80% to maximize long-term lithium-ion battery health.
- **Steps**: 1. Open Vorssaint settings. 2. Navigate to Battery / Charge Limiter. 3. Adjust slider or enter target percentage (e.g., 80%). 4. Enable Charge Limiter.

### 2. Top Up
- **Description**: Temporarily raises charge limit to 100% for a long day on the road, reverting to previous limit upon unplugging.
- **Details**: One-time override flag resetting on physical disconnect.
- **Examples**: Clicking "Top Up" in menu bar before traveling so the battery reaches 100% once, then reverts to 80% next day.
- **Steps**: 1. Click Top Up action from menu bar or quick panel. 2. Confirm temporary 100% charge target. 3. Unplug Mac to automatically revert to default limit.

### 3. Hardware Battery Percentage
- **Description**: Display the battery management system's raw hardware percentage alongside macOS's reported percentage in the menu bar and popover.
- **Details**: Secondary telemetry data rendering comparing firmware SoC vs OS SoC.
- **Examples**: Showing raw sensor value (e.g., 81.4%) next to rounded OS percentage (81%).
- **Steps**: 1. Enable Hardware Battery Percentage in menu bar settings. 2. Observe secondary telemetry readout in battery popover.

### 4. Live Status Icons
- **Description**: Menu bar icon style reflecting real-time state: charging, holding charge, or running on battery.
- **Details**: Dynamic SF Symbols / custom status item rendering based on power state.
- **Examples**: Bolt icon when charging, pause/shield icon when holding charge at limit, battery icon when running on battery.
- **Steps**: 1. Connect or disconnect power adapter. 2. Observe menu bar icon update instantly to reflect current power state.

### 5. Disable Sleep until Charge Limit
- **Description**: Keeps the MacBook awake in clamshell/sleep mode until the target charge limit is reached, then allows sleep.
- **Details**: Power management assertions (`IOPMAssertion`) tied to charge threshold monitoring.
- **Examples**: Closing MacBook lid while plugged in at 75% with an 80% limit; Mac stays awake until 80% is reached, then sleeps.
- **Steps**: 1. Enable "Disable Sleep until Charge Limit". 2. Plug in Mac below target limit. 3. Close lid or idle; observe system staying awake until target limit is attained.

### 6. Stop Charging when Sleeping
- **Description**: Pauses charging right before the MacBook goes to sleep so the battery stays at its current level instead of charging to 100%.
- **Details**: System sleep notification observers (`NSWorkspace.willSleepNotification`).
- **Examples**: Mac goes to sleep at 60% charge; without feature it might trickle charge to 100% during deep sleep; with feature, charging is halted prior to sleep.
- **Steps**: 1. Enable "Stop Charging when Sleeping". 2. Put Mac to sleep while plugged in. 3. Verify charging pauses upon sleep entry.

### 7. Stop Charging when App Closed
- **Description**: Ensures the set charge limit remains active even when the AlDente / Vorssaint app is closed (Apple Silicon only).
- **Details**: Daemon or persistent system state registration.
- **Examples**: Quitting Vorssaint app entirely while plugged in at 80% limit; SMC maintains charge hold without app running.
- **Steps**: 1. Set charge limit. 2. Quit Vorssaint application. 3. Verify via system power status that charge limit enforcement remains active.

### 8. Discharge
- **Description**: Allows discharging to a lower, healthier charge level while plugged in by simulating unplugging until target limit is reached.
- **Details**: SMC command / battery state override to allow discharging under AC power.
- **Examples**: Plugged in at 90% with limit set to 60%; activating Discharge draws power from battery down to 60% while connected to charger.
- **Steps**: 1. Click Discharge action. 2. Monitor battery level dropping to target limit while staying connected to power source.

### 9. Automatic Discharge
- **Description**: Automatically discharges the MacBook when the charge limit is set lower than the current battery percentage while plugged in.
- **Details**: Reactive state machine triggering Discharge when limit < SoC.
- **Examples**: Lowering limit from 90% to 70% while plugged in automatically initiates discharging until 70% is reached.
- **Steps**: 1. Adjust charge limit below current battery percentage. 2. Observe automatic initiation and completion of discharge cycle.

### 10. Sailing Mode
- **Description**: Extends Charge Limiter with a lower hysteresis interval (e.g., 5-10%) to prevent micro-charging.
- **Details**: Hysteresis deadband around the charge limit.
- **Examples**: With 80% limit and 5% hysteresis, battery discharges down to 75% before recharging back to 80%, avoiding constant 80% trickle charging.
- **Steps**: 1. Enable Sailing Mode. 2. Configure hysteresis window (e.g., 5%). 3. Observe discharge/charge cycling within deadband.

### 11. Heat Protection
- **Description**: Automatically halts charging if battery temperature exceeds a threshold (e.g., 35°C) with a 5-minute hysteresis countdown.
- **Details**: Thermal sensor polling and timer-based hysteresis logic.
- **Examples**: Heavy compilation raises battery temperature to 38°C; charging pauses automatically until temperature cools below threshold plus hysteresis.
- **Steps**: 1. Configure Heat Protection temperature threshold. 2. Monitor thermal sensor telemetry during high workloads. 3. Verify charging halts when threshold is crossed.

### 12. Control MagSafe LED
- **Description**: Uses MagSafe LED (MagSafe 3 / MagSafe 2) to indicate charging state (Green for limit reached, Orange for charging/discharging, blinking options).
- **Details**: Low-level SMC / hardware LED control APIs.
- **Examples**: MagSafe LED turns green when battery reaches charge limit even though plugged in.
- **Steps**: 1. Enable MagSafe LED control. 2. Reach charge limit; observe LED change from amber/orange to green.

### 13. Fast User Switching
- **Description**: Supports multiple macOS user accounts, maintaining persistence and preventing brief charging periods during user switches.
- **Details**: Multi-session state coordination and background daemon handling.
- **Examples**: Switching from User A to User B without resetting charge limit or causing transient power spikes.
- **Steps**: 1. Log in to User A with active charge limit. 2. Fast switch to User B. 3. Verify background daemon preserves limit state across session switches.

### 14. Calibration Mode
- **Description**: Automated one-click cycle: charge to 100%, discharge to 10%, charge to 100%, hold 1 hour, restore preset limit.
- **Details**: Multi-stage state machine orchestration bypassing heat protection temporarily.
- **Examples**: Running monthly battery calibration to recalibrate battery percentage reporting accuracy.
- **Steps**: 1. Initiate Calibration Mode. 2. Allow automated charge-discharge-charge cycle to complete. 3. Verify previous limit is restored.

### 15. Schedule
- **Description**: Task scheduler supporting automated actions (Set Charge Limit, Calibration, Top Up, Pause, Low Power Mode) with repeat intervals and "Catch Up on Missed Tasks".
- **Details**: Cron-like scheduling engine with persistence and wake-up catch-up logic.
- **Examples**: Schedule a daily Top Up at 8:00 AM and Charge Limit adjustment at 6:00 PM.
- **Steps**: 1. Open Schedule settings. 2. Create new task with action, time, and repeat days. 3. Save schedule and verify execution log.

### 16. Automatic Scheduled Calibration
- **Description**: Recurring scheduled tasks specifically for running Calibration Mode monthly or biweekly.
- **Details**: Integration of the Scheduler engine with Calibration Mode.
- **Examples**: Automatically trigger battery calibration on the 1st of every month.
- **Steps**: 1. Configure Automatic Scheduled Calibration frequency (e.g., monthly). 2. Ensure Mac remains connected to power on scheduled date.

### 17. Power Flow
- **Description**: Real-time Sankey diagram visualization of power flow from charger, battery, and system consumption under various operational scenarios.
- **Details**: Advanced custom UI rendering of real-time power metrics telemetry.
- **Examples**: Visualizing 65W input from USB-C charger splitting into 15W system load and 50W battery charging.
- **Steps**: 1. Open Power Flow panel / system monitor. 2. Observe real-time animated graphic of power sources and sinks.

### 18. Apple Shortcuts Integration
- **Description**: Comprehensive App Intents / Shortcuts support for toggling modes, setting limits, querying state, and automating workflows.
- **Details**: Swift App Intents framework integration exposing all app capabilities to macOS Shortcuts.
- **Examples**: Creating a Shortcut automation that sets charge limit to 60% when connecting to home Wi-Fi.
- **Steps**: 1. Open Shortcuts app on macOS. 2. Search for Vorssaint actions (Set Limit, Toggle Calibration, Query Status). 3. Build and run custom shortcut workflow.
