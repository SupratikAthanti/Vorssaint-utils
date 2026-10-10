# Tests-first security review — 2026-10-09

Baseline reviewed commit: `0d7939738cca623d32da9bac470750ea323f7840` (branch `New-Functions`).

## Remediation and second review

The baseline sections below are historical evidence, not a description of the repaired tree. Local checkpoint commits `06f93872` and `61edf412` contain battery/test isolation and filesystem hardening; subsequent remediation covers networking, parsers, imported authority, privacy, and second-pass findings. No commits were pushed.

### Changes by finding

- **S1:** unique owner-only updater work directory on the destination filesystem; copied DMG verified and mounted read-only; protected stage and backup; predictable recursive cleanup removed. Elevated installs accept only direct, non-symlink app paths under root-owned, mode-0755 `/Applications` without an extended ACL. Work-directory ACLs are stripped. Published elevated bundles remain root-owned, relaunch drops UID as well as selecting the GUI session, and failed rollback backups are retained. Custom directories requiring elevation are intentionally refused, not silently supported.
- **S2:** injected hardware/telemetry/clock/defaults, no native battery singleton in the unit-test build, explicit control opt-in, fresh telemetry and range gates, hardware read-back, error reporting, write-ahead recovery debt, thermal/discharge cleanup, shutdown and sleep/wake handling. The production adapter alone opens SMC. Display group/profile/favorites tests now execute current production services rather than test-owned algorithms; duplicate fingerprints and invalid layout coordinates are refused. DDC tests are registered and concrete test-input defects removed.
- **S3:** no-follow descriptor traversal, descriptor-relative exclusive temporary creation and rename, permission/owner checks before publication, error propagation, and macOS ACL removal. Redirected ancestors fail closed; leaf symlinks are replaced, not followed. This is not encryption or a same-account security boundary. Nonstandard symlinked home/store ancestors may be refused.
- **S4:** validate size before multiplication, reject duplicate headers and nonfinite/malformed samples, bound import reads and parser bytes to 32 MiB.
- **S5:** shared incremental response collector used for sharing uploads/deletions, feedback, and self-update metadata; byte ceilings enforced before retaining each chunk, credential/cookie storage disabled, redirects refused. Existing feedback and video-upload time budgets preserved. Added delegate tests and real loopback transport checks.
- **S6:** explicitly documented internal-resolving HTTPS feeds as supported. The syntax filter is not claimed to prevent DNS rebinding or internal-address access. Cookies and credentials remain disabled. This is a clarified policy, not a public-destination enforcement implementation.
- **S7:** executable-capable launcher links excluded from portable export/import and import clearing; locally trusted links retained. Backup reads bounded to 8 MiB before plist parsing, with no uncoordinated fallback after coordination failure.
- **S8:** lock-screen calendar titles/colors replaced by generic localized next/ongoing labels; calendar timing remains visible. Documentation now explains that enabled lock-screen countdowns restart calendar readings in memory.
- **S9:** disk-image commands use the existing bounded runner with a 60-second deadline and 2 MiB retained-output limit.

### Additional findings during re-review

Re-examined repaired battery transitions, updater cleanup/relaunch/destination checks, descriptor storage, response collection, and changed call sites. Fixed: polling/preference changes overriding sleep policy before wake; root relaunch fallback; recursive cleanup after failed image detach; deletion of a backup when rollback itself failed; extended ACL and nested app-path acceptance at the elevated destination boundary. Tests now assert that polling cannot undo the sleep hold.

This was another targeted manual pass, not exhaustive certification. Remaining **validation blockers**, not passes: optimized macOS build/typecheck, full unit executable and mutations, real admin/nonadmin updater install and rollback tests, codesign/Gatekeeper rejection, Apple ACL behavior, lock-screen GUI/accessibility checks, XPC/TCC negatives, and hardware SMC read-back/safety tests. In particular, shell syntax and source contracts do not prove elevated filesystem integrity. Shell copy/mount/assessment commands still need macOS fault-injection/deadline testing; unexpected FIFOs/devices in download inputs and interrupted installation are residual availability/recovery cases to test. Same-account attackers remain outside the private-store confidentiality boundary.

### Verification actually rerun on Linux

A signature-verified Swift 6.0.3 toolchain was unpacked under ignored `build/security-toolchain`; no system-wide install was performed.

| Check | Final result | Scope |
|---|---|---|
| Production battery engine with inert hardware and isolated defaults | PASS: 30 assertions, plus 30 physical/software combinations | No Apple hardware/Combine runtime |
| Production private store filesystem regressions | PASS: 8 assertions | Linux POSIX; macOS ACL branch untested |
| Current extracted production LUT parser | PASS: 11 assertions | Overflow headers, duplicates, nonfinite samples, sample ordering/count |
| Production HTTP delegate regressions | PASS: 4 assertions | Incremental overflow and redirect failure |
| Real HTTP collector requests to loopback fixture | PASS: 4 requests | Small response, excessive Content-Length, excessive unknown-length body, redirect; fixture stopped afterward |
| Swift collector typecheck and changed Swift source parsing | PASS | Parsing does not resolve Apple APIs or prove full app compilation |
| Test source generation and Python AST checks | PASS | Extraction/syntax, not full macOS suite |
| Final extracted installer `/bin/sh -n` and `git diff --check` | PASS | Syntax/whitespace only |

The Linux battery test link emits an RWX-segment warning; the portable executable is an ignored verification artifact, not a release app. No claim is made that Linux checks replace the macOS release gates.

---

## Executive summary

The repository has meaningful production-helper and extracted-production-method tests, but its test count is not evidence that all advertised features work or are safe. Several newer display tests test implementations defined entirely inside the tests. Battery “simulation” tests are not isolated simulations. The current standalone test compilation list also contains concrete defects, independently of Linux's inability to build the app.

Highest priorities:

1. Make battery tests incapable of writing hardware or real preferences before repairing their build inputs.
2. Make battery hardware operations verified, failure-aware, explicitly enabled, and recoverable.
3. Protect the elevated updater's inputs and staging area against path replacement between verification and use.
4. Make private storage fail closed when permissions cannot be established.
5. Replace test-owned feature implementations and security source-text assertions with production behavior tests.

This was a targeted manual source review, not exhaustive certification of all 989 indexed project files. No application fixes, deployment, signing changes, system configuration changes, or git commits were made. The remote sharing backend was not present and its retention/moderation claims were not independently verified.

## Environment and evidence limits

Host: Linux aarch64. No Swift compiler, Apple SDK, or macOS runtime was installed. Swift compilation, typecheck, full application selftest, XCTest-equivalent executable, code-signing assessment, XPC enforcement, TCC, GUI interaction, SMC writes, and complete mutation runs could not be executed.

A Debian zsh package and its common files were downloaded and unpacked under `/tmp/vorssaint-security-review-tools`; no system package installation was performed. Test source generation wrote ignored `build/generated-tests` outputs. The only intended tracked addition is this report.

Labels below distinguish confirmed source defects, Linux behavior reproductions, and macOS-dependent risks. No claim of a proven root exploit or actual hardware damage is made.

## 1. Do the tests test the application?

### 1.1 Useful testing infrastructure

- `Tests/TestSuite.swift:12-52` records failed assertions, reports file/line diagnostics, rejects non-finite numeric comparisons, fails a selected group that executes no assertions, and returns a failing process exit code.
- `Tests/MetricsTests.swift:206-243` rejects unknown suite arguments. The `simulation` group is excluded from default execution, but its sources are still compiled.
- `Tests/generate_sources.py:19-44` reads current production declarations on every generation. Generated tests are not simply stale maintained copies. This is valuable for testing control flow with substituted transport, scheduling, UI, and defaults.
- Existing tests exercise real filesystem behavior and production helpers: storage permission modes (`StorageFeatureTests`), uninstaller ownership/path replacement (`AppManagementFeatureTests`), file promises (`ShelfFilePromiseTests`), bounded subprocesses (`NetworkFeatureTests`), and sharing response schemas (`ScreenshotFeatureTests`, `RecorderFeatureTests`).
- `Tests/mutation_checks.py:298-349` requires an unmodified passing baseline and an intended assertion failure; compiler errors and timeouts do not count as mutation detection. All 61 current mutation replacement anchors matched once. The mutations themselves were NOT run.

Extracted methods still do not prove the full production type's initialization, platform integrations, actor/thread behavior, or real permission enforcement. Some generated source transformations change visibility, clocks, API calls, and availability lookup. Those assumptions require separate integration tests.

### 1.2 Confirmed test compilation-input defects — blocking

The actual zsh-expanded `TEST_SOURCES` array was inspected without running the build/install script:

- `build.sh:440` names nonexistent `Sources/Vorssaint/App/StatusItemPlacementSupport.swift`.
- `build.sh:554-555` includes `Tests/BatteryManagerTests.swift` through `Tests/*.swift` and explicitly again. This also duplicates its object-map entry.
- `MockSMCClientTests` and `BatteryManager.swift` reference `SMCClient`, but no `SMCClient` declaration exists in the selected sources or generated test outputs.
- `SimulationDoubleStateMachinesTests` references `VirtualDisplayService`, `Display3DLUTService`, `DisplayAutomationService`, and `DisplayDiagnosticsConsoleService`; none is defined in the test compilation inputs. Selecting another suite does not remove these files from compilation.
- `Tests/DisplayProfileTests.swift:31-32` has a non-`mutating` struct method assigning `storedData`, an independent Swift source error.

These are concrete static build defects, not observed Swift compiler output. Repair them and rerun on macOS, but do not simply add real hardware services to the test target without isolation.

### 1.3 Tests that validate test-owned implementations — high assurance gap

Examples:

- `Tests/DisplayGroupTests.swift:14-134` defines its own display models and complete `MockDisplayManager.updateControl`; it never calls `DisplayGroupService`.
- `Tests/DisplayProfileTests.swift:27-88` defines its own persistence, debounce, and application algorithm; `LayoutApplier` returns simulated success without applying a layout. It never tests `DisplayProfileService`.
- `Tests/DisplayFavoritesTests.swift:34-93` defines its own store and validator.

These tests can pass while production behavior is deleted or broken. Their assertions describe useful requirements but should call real production logic with fake hardware boundaries, not implement that logic themselves.

A concrete missed production failure: `DisplayProfileService.swift:94` constructs `Dictionary(uniqueKeysWithValues:)` from fingerprints composed of vendor, model, serial, and dimensions (`:209-215`). Two identical monitors with missing/duplicate serials can collide and trap. The test uses invented unique fingerprints and a different application algorithm. Treat this as a confirmed crash precondition; actual monitor reproduction needs macOS.

### 1.4 Battery “simulation” tests do not simulate the claimed events

- `ThermalStateSimulationTests.swift:15-33` never injects a 36°C reading or a cooling reading. It repeatedly calls evaluation and checks configuration flags, not a thermal trip, hysteresis recovery, hardware restoration, or priority over discharge.
- `PowerEventSimulationTests.swift:20` polls real telemetry rather than injecting AC removal.
- Its sleep/wake notifications (`:28-30`) are posted to `NotificationCenter.default`, while production observes `NSWorkspace.shared.notificationCenter` (`BatteryManager.swift:184-185`). The test does not assert resulting hardware actions.
- `BatteryManagerTests` mainly checks values it just assigned and initial calibration state. It does not inject a clock, telemetry source, or SMC transport.
- `SMCRegisterStore` in `MockSMCClientTests` calls the production codec, so it meaningfully tests encoding. It is not injected into `BatteryManager`, and does not prove battery hardware behavior.
- `SimulationDoubleStateMachinesTests` does not perform systematic two-machine exploration. Its states are mostly initial values and log strings. `VirtualDisplayService.swift:60-88` allocates simulated IDs, not real virtual display resources. Its one valid LUT fixture tests parsing only; `importAndApplyLUT` stores metadata and does not apply a color pipeline.
- `DDCDisplaySimulatorTests` contains useful production packet-parser calls but has no `.run` invocation in the compiled test inputs. It is not currently executed.

### 1.5 Source-text tests are not executable security tests

`UpdateFeatureTests.swift:963-1001` checks that installer strings contain signature commands, markers, and ownership changes. It checks relative text positions for DMG verification. These can pass if an attacker can replace paths between those commands, or if a relevant command is unreachable or incorrectly handled. `UpdateAdminInstallTests` tests overlay/prompt ordering with a fake authorization result, not root filesystem safety.

There are at least 27 top-level Swift test files containing source/disk-read expressions in a coarse scan; this is not a count of ineffective tests, since many of those files also contain genuine behavior tests. Use text contracts as supplementary wiring checks, not the primary security evidence.

## 2. Linux checks actually performed

| Check | Result | What it proves |
|---|---|---|
| Existing `PreferenceCleanupTests.sh` through local zsh | PASS, rerun | Actual extracted cleanup handles delayed writes, preserves an unrelated file, rejects persistent writers |
| Existing uninstall pure-state fixture section | PASS: **28 cases** | Actual extracted `spaces_leftover` decisions match fixtures; macOS probes/preflight excluded |
| zsh `-n` on build script, five Tools scripts, two test scripts | PASS: 8 files | Shell syntax only, not Apple commands |
| `Tests/generate_sources.py` | PASS | Current extraction anchors succeed; 128 Swift outputs generated |
| Generator second-run SHA-256 comparison | PASS | All 128 outputs deterministic at reviewed source state |
| Python AST parsing of generator and mutation script | PASS | Python syntax only |
| Mutation replacement-anchor audit | PASS: 61/61 | Fixtures still locate intended code; no mutation effectiveness claim |
| Resource plist/entitlement parsing with `plistlib` | PASS: 3 files | Serialization syntax only |
| Extracted updater script `/bin/sh -n` | PASS | POSIX shell syntax of extracted script |
| Actual updater swap-fragment sandbox test | Replacement reproduced | Post-verification staging bytes are not tied to swap; no root/macOS exploit executed |
| Full Swift tests/build/typecheck/selftest | NOT RUN | No Swift compiler or Apple frameworks |
| Full uninstall shell test and mutation suite | NOT RUN | Need macOS `plutil`, Apple tools/APFS and Swift |

Correction to an interim console message: the extracted uninstall section has 28 `expect` invocations, not 29. It was counted explicitly after execution.

An initial ShellCheck run forced zsh scripts into Bash mode and failed on zsh-specific syntax. Those diagnostics are not valid project lint failures; native zsh syntax checks were used instead. Two intermediate updater-fragment harness attempts failed during extraction/status checking; the corrected final behavior check passed. These attempts are not application test passes.

## 3. Security and safety findings

### S1. Elevated updater verifies mutable paths, then uses them — HIGH, conditional local integrity/privilege risk

Evidence: `UpdateInstallerSupport.swift:66-77, 102-143`; `UpdateService.swift:278-284`.

The DMG is moved to a fixed user-temporary path, verified by pathname, and later mounted by pathname. The staged app uses predictable `$DIR/.$NAME.update-new`. The script copies, reads version metadata, assesses Gatekeeper, checks signatures, and subsequently moves that same path into place. There is no protected snapshot or descriptor identity binding across those steps. The elevated branch runs these filesystem operations as root; the marker writer correctly drops privileges, but that does not protect the other paths.

Where another local process can modify the DMG, stage, or a parent directory, it can change what subsequent steps consume. In a temporary sandbox, replacement content inserted after the conceptual verification boundary was installed by the unmodified real swap fragment. This proves the gap in the swap contract; it does not prove that an attacker can win a race against macOS assessment, bypass hardened runtime, or execute as root. Exploitability depends on actual directory ownership, copied modes/ACLs, and filesystem behavior. A user-writable custom app directory used during a forced administrator retry deserves particular scrutiny.

Recommendation: use a unique root-owned `0700` work directory for elevated operations; copy the DMG into it before verification; mount that protected copy read-only; stage and verify in protected storage on the target filesystem; securely validate destination ancestors; avoid predictable paths and recursive operations on attacker-changeable trees; commit through a controlled atomic rename. Do not treat a second pathname-based signature check alone as a complete race fix. Add adversarial integration tests that replace inputs/parents at each boundary.

Positive: expected team and app identifier checks, version match, rollback staging, bounded DMG download, inline elevated script, and deprivileged marker writes are substantial defenses already present.

### S2. Battery engine and tests are not fail-safe or hardware-isolated — HIGH safety/assurance issue

Evidence: `BatteryManager.swift:15, 20-26, 143-196, 244-328, 361-388, 435-454`; `AppDelegate.swift:144`.

- The engine opens `SMCClient` directly, loads standard preferences, registers real observers, and starts polling. It is unconditionally initialized at app launch, with no explicit master control opt-in in this class.
- Default/past values such as plugged-in=true, charge=80, temperature=28.5 can drive evaluation while preference setters run, before fresh telemetry arrives.
- Every charging/discharge/LED write discards errors with `try?`. UI booleans describe requested state even if hardware did not accept it; there is no read-back confirmation.
- Thermal protection returns after inhibiting charging without explicitly clearing already active forced discharge or releasing an existing sleep assertion.
- Calibration can advance at 10% without clearing discharge in that transition; stopping calibration below the configured active limit can also take a branch that does not clear it immediately.
- No shutdown restoration or crash recovery for these battery writes appears in the reviewed engine. `stopChargingWhenAppClosed` is stored and exposed in settings but no implementation consuming it was found outside storage/UI.
- Settings integers are not range-validated by this engine. `activeLimit - sailingHysteresis` can overflow for extreme persisted values.

On Macs supporting these write keys, the tests' use of `BatteryManager.shared` reaches real hardware writes and the test process's standard preferences. The separate mock register store does not prevent this. Actual permission/support requirements for CH0I/CH0D and physical consequences need hardware validation; they are not assumed here.

Recommendation: inject SMC, telemetry, clock, defaults, and lifecycle interfaces; tests must supply a transport that cannot open IOKit. Require fresh valid telemetry and explicit feature enablement before writes. Validate ranges and finiteness, preserve verified state separately from requested state, report write failures, read back critical writes, restore discharge/assertions on every safety transition, and define shutdown/crash recovery. Test temperatures, AC transitions, calibration, invalid settings, partial write failure, and cleanup using assertions on the fake transport's log.

### S3. Private storage reports success even when privacy enforcement fails — MEDIUM, confirmed source defect

Evidence: `PrivateFileStore.swift:33-54`; `StorageFeatureTests.swift:63-113`.

Directory and file permission changes are ignored with `try?`, followed by `return true`. Consequently, privacy-sensitive callers can report durable private storage even when tightening fails. Existing world-readable directories can remain readable. The abstraction uses pathname operations, does not reject redirected ancestors, does not establish secure file descriptors, and does not explicitly address ACLs. File mode is tightened after atomic write rather than guaranteed at creation; any exposure window depends on Foundation's temporary-file implementation and parent access.

Impact is conditional on an accessible/insecure store, permissions/ACL behavior, and the failure encountered. The confirmed defect is false-success handling, not demonstrated cross-user data theft. POSIX owner-only mode is not encryption and does not protect against the same account or root.

Recommendation: propagate permission failures; create private files/directories securely before writing; use exclusive/no-follow descriptor operations where needed; verify ownership/type and effective access policy; protect all store ancestors; handle ACLs according to an explicit macOS policy. Test failing chmod, existing permissive/ACL-bearing roots, symlinks, and replacement races. Existing happy-path mode tests are useful but insufficient.

### S4. LUT validation can overflow before it rejects an invalid size — MEDIUM crash defect, currently limited reachability

Evidence: `Display3DLUTService.swift:57-83, 88-99`.

`expectedSamples = lutSize * lutSize * lutSize` precedes the `2...256` guard. A single header `LUT_3D_SIZE 2097152` produces `2^63`, beyond the 64-bit signed maximum, and Swift checked multiplication can trap. This arithmetic precondition was validated on Linux; the Swift function itself was not executed. File import also reads the entire input without a byte limit; non-finite Float samples are accepted as numeric tokens.

Recommendation: reject the size before multiplication, use checked arithmetic, bound file bytes/lines/entries, and require finite samples and coherent headers. Add malformed/oversized/duplicate-header/NaN tests against the production parser. Only the explicit simulation test references this service outside its own source in the inspected tree; no ordinary user import caller was found, so immediate user-facing exploitability is limited.

### S5. Shared/feedback response limits are applied after full buffering — MEDIUM availability risk

Evidence: `ScreenshotShareService.swift:108-120, 180`; `RecordingShareService.swift:113-125, 178`; `FeedbackService.swift:102-106`; `UpdateService.swift:130`.

Async `upload`/`data` and callback data tasks collect the complete response before checking its byte count. A slow/oversized response can consume substantial memory within the timeout. Delete endpoints discard returned Data only after buffering it. The self-update metadata response has no explicit size bound.

The attacker generally needs control of a contacted endpoint, compromise of that service, or a developer endpoint override; ordinary network interception cannot bypass valid TLS. This is not a universal remote unauthenticated exploit.

Recommendation: reuse a bounded streaming response collector with status, incremental bytes, resource timeout, and redirect policy. Set credential storage explicitly where it is not needed. Do not assert cross-origin Authorization leakage without testing Foundation's actual redirect behavior; this review did not establish that.

### S6. “Public URL” validation does not ensure a public destination — LOW/MEDIUM conditional request-forgery risk

Evidence: `AppUpdateFeedSupport.swift:44-52`; `AppUpdateFeedLoader.swift:59-69`.

Validation restricts syntax and HTTPS, rejecting obvious local names/IP literals. It does not check resolved IP addresses, alternate local DNS names, or explicit ports. A hostname with letters/dots can resolve to a private/loopback address, including after redirect. Installed-app metadata controls these feed URLs.

Impact: unintended HTTPS GETs to local/internal services when online app checking is enabled. Valid TLS and absence of cookies/credentials limit the attack. A local malicious installed app already has significant capabilities, so do not overstate incremental privilege.

Recommendation: either explicitly document support for internal feeds rather than promising public-only, or enforce a public-destination policy through a transport/proxy that handles DNS resolution, redirects, and rebinding consistently. Test private-resolving hosts and nonstandard ports without probing unrelated live services.

### S7. Imported settings carry executable local authority — MEDIUM trust-boundary concern

Evidence: `SettingsBackupSupport.swift:55, 209-222, 413-416`; `SettingsBackup.swift:52-69, 75-136`; `CommandBarLinks.swift:18-20, 190-205`; `CommandBarScriptRunner.swift:62-90`; `CommandBarService.swift:1757-1767`.

Backups can import `commandBarLinks`, including script paths and execution flags. The sanitizer does not strip script links or require fresh authorization for them. Script matching can execute an imported path when typing pauses, before Return. Import has a general confirmation, but the reviewed flow does not separately establish trust for executable entries.

This is not automatic execution just from reading a backup, nor evidence of arbitrary shell-string injection: scripts run as an executable plus an argument. It is a social-engineering boundary where a configuration file can replace previously trusted launcher actions with side-effecting local commands. Similar backup portability logic already excludes image paths and folder bookmarks as local authority, making this omission noteworthy.

Recommendation: exclude script paths/automatic execution flags from portable imports, or import them disabled and require explicit per-script approval showing the resolved path and behavior. Separate URL/path configuration from executable authority. Also bound backup bytes before plist parsing; currently the entire file is read before validation.

### S8. Lock-screen calendar disclosure contradicts privacy documentation — MEDIUM opt-in privacy issue

Evidence: `NotchLockScreenService.swift:115-120, 178-187`; `UI/Notch/NotchLockScreenView.swift:370-380`; `Defaults.swift:1503`; `docs/PRIVACY.md`, Optional notch features.

With the disabled-by-default lock-screen feature enabled and calendar countdown/time-left active (or a chosen event), the lock-screen service restarts calendar access and displays event titles over the locked session. The privacy document says event text is cleared when the Mac locks, without explaining this exception. Download and agent views deliberately redact filenames/project names, but calendar titles are exposed.

Recommendation: default to redacted calendar text while locked; require separate informed opt-in for event titles; document exactly what remains visible without authentication. Test both redacted and explicitly enabled title policies. This is disclosure to someone physically viewing the locked Mac, not an authentication bypass.

### S9. Some disk-image subprocesses have no deadline/output bound — LOW/MEDIUM availability issue

Evidence: `DiskImageInstallerService.swift:445-460`.

The service has its own `Process` runner using `readDataToEndOfFile` and `waitUntilExit`, without the shared bounded runner's deadline or output limit. A stalled image/tool/filesystem can indefinitely block the serial installation workflow. This does not execute an arbitrary command string; executable paths and argument arrays are fixed.

Recommendation: use the existing bounded process abstraction, with explicit per-command timeouts and bounded output, and test a stalled child and excessive output.

## 4. Defenses observed and claims not made

- Fan helper: listener sets a team-and-identifier signing requirement before activation (`FanControlHelper/main.swift:601`); client/helper requirements are explicit in `FanControlXPC.swift`. Do NOT call the listener unauthenticated merely because its delegate returns true. Enforcement still needs macOS negative-identity tests.
- Fan ownership files use `O_NOFOLLOW`, exclusive marker creation, root ownership/mode/link-count checks; watchdog handles heartbeat, temperature failures, disconnect, and recovery. These are useful patterns for battery control too.
- SMC payload sizes are bounded and byte counts checked in `SMCClient.writeBytes`; no payload-buffer overflow was established.
- Sudoers permits two exact pmset commands and uses numeric UID, avoiding free-form username injection. It grants the account that narrow capability, not exclusively this app.
- Shell/admin commands use argument arrays and appropriate quoting in reviewed boundaries. No broad remote command-injection finding was established.
- Uninstaller tracks inode/device identities, constrains roots, checks signed groups, and refuses many symlink/replacement cases. Residual check-to-use races deserve integration testing, particularly Finder-mediated authorization, but this review did not prove an arbitrary protected-file deletion exploit.
- Feed XML disables external entity resolution and aborts on entity declarations; byte/depth/entry limits exist. No XXE finding was established.
- Sharing has explicit enablement, bounded upload payloads, strict response token/path schemas, private token storage, and revocation fallback. Server-side expiry and metadata stripping remain unverified.
- Clipboard concealment markers are honored before reading content. Sensitive-text heuristics are best-effort, not comprehensive secret detection. Clearing the system clipboard intentionally does not clear stored history and is documented.
- Entitlements do not enable JIT, unsigned executable memory, or disabled library validation. The app is intentionally unsandboxed; TCC and release hardened-runtime configuration require macOS verification.
- Release actions are SHA-pinned, signing is environment-gated, read/write permissions are separated, refs rechecked, and signed/notarized assets verified. Environment approvals and repository protection settings cannot be proven from workflow YAML alone.

## 5. Remediation and verification order

1. **Contain tests first:** inject inert SMC/defaults/telemetry adapters; prove no real IOKit open or standard-domain preference writes occur in any unit suite.
2. **Restore build integrity:** remove duplicate/missing inputs, correct struct mutation, explicitly include needed isolated production logic; build application and test executable separately on macOS.
3. **Repair updater trust boundaries:** protected unique elevated staging/input snapshots; adversarial filesystem tests, genuine wrong-team/unsigned/tampered-DMG rejection, cancellation/rollback, standard-user elevated install, and custom-directory cases.
4. **Repair battery state handling:** requested versus verified state, telemetry freshness, failure recovery and shutdown; exhaustive transition tests with transport logs.
5. **Repair storage and parsers:** fail-closed private creation, permission/ACL/error tests, LUT bounds/finite values, duplicate-monitor fingerprints, backup size limits and executable-import approval.
6. **Improve coverage honesty:** replace test-owned display algorithms, register DDC tests, turn security string checks into executable behavior tests; add targeted mutations for signature gates, bounds, thermal restoration, and privacy failures.
7. **Add practical CI tiers:** portable Foundation/pure-logic tests for Linux where feasible; macOS integration/signing/XPC/TCC tests in macOS CI. Current `Package.swift` is editor-indexing support, has no test target, and cannot substitute for `build.sh`.

Before calling this branch release-ready, run the final macOS optimized application build, selftest, repaired complete unit suite, security-focused mutations, and the actual installation/permission/hardware interfaces with explicit recorded results. Linux passes above do not replace those checks.
