# Feature Specification: Audio Device Selection in the Floating Window

**Branch**: `009-audio-device-selector`
**Created**: 2026-03-20
**Status**: Draft
**Input**: User description: "Select the current audio device in the floating window with support for the built-in MacBook microphone, USB devices, Bluetooth devices (AirPods, headsets), Continuity devices (iPhone). Handling A2DP→HFP switching, automatic fallback to the system default device on disconnect, sample rate validation, diagnostic logging."

## Clarifications

### Session 2026-03-20

- Q: When a device disconnects during recording — stop recording or continue on System Default? → A: Stop recording, show notification "Device disconnected", switch selection to System Default. The user starts recording again manually.
- Q: When does Bluetooth A2DP→HFP switching occur? → A: When the device is changed in the menu, if recording is already active — full audio engine restart with HFP. If recording is not active — profile switching is deferred until recording starts.
- Q: Device change during active recording (any type) — restart or stop? → A: If recording is active — automatic restart on the new device. If recording is not active — only the selection in the menu changes, recording starts on pressing the "Start" button.
- Q: How many items are in the top section above the separator? → A: One item — "System Default Input".
- Q: Which UI element is used for device selection? → A: The existing dropdown menu component (the same one used for selecting input/output language) — a button inside the floating window summary.
- Q: What does the user see during Bluetooth A2DP→HFP switching (up to 5 sec)? → A: If switching takes >200ms — show a spinner and the "Switching…" message in the popup window, the Start/Stop button is disabled. If <200ms — show nothing.
- Q: Should the A2DP→HFP switching logic be unified across all scenarios (first start of recording, device change, reconnect after disconnection)? → A: Yes. There must be a single unified method that: (1) checks the current device profile (A2DP/HFP), (2) if the profile is not HFP — initiates A2DP→HFP switching, (3) subscribes to CoreAudio events and waits for confirmation from the OS that the switch is complete, (4) only after confirmation allows the device to be used for recording. After stopping recording — return to A2DP. This method is used in all three scenarios without code duplication.
- Q: Is additional logging required for the unified profile switching process? → A: Yes. Each call to the unified method must log: call context (first start / device change / reconnect), current profile status before the check, whether switching was needed, subscription to OS events, receipt of confirmation from the OS, final result. After recording stops — log the return to A2DP.
- Q: How to reliably determine the current Bluetooth profile (A2DP vs HFP) when macOS does not provide a direct API? → A: Use a composite analysis of three properties: (1) `kAudioDevicePropertyNominalSampleRate` — primary indicator; (2) `kAudioDevicePropertyStreamConfiguration` (input scope) — presence of input channels = HFP (the most reliable single indicator, because in A2DP there are zero input channels); (3) `kAudioDevicePropertyStreamConfiguration` (output scope) — HFP = mono (1 channel), A2DP = stereo (2 channels). The transport type (`kAudioDevicePropertyTransportType`) is used as a filter so that the logic does not trigger on USB microphones with a low sample rate. When at least one property has changed — re-read all three and recompute the profile.
- Q: How to handle the transitional state during A2DP→HFP switching when the device may report an intermediate incorrect sample rate? → A: After receiving notification about a property change — wait 300 ms for stabilization, then re-read all three properties. If the values changed compared to the previous reading — wait another 300 ms (debounce). Consider the profile stabilized when two consecutive readings produce the same result.
- Q: How is the "Device disconnected" / "Device unavailable" notification displayed? → A: In the standard way for the application — an icon and a text message in the floating window (like all other errors).
- Q: What happens at startup if the saved device is unavailable? → A: Silent fallback to System Default without notification.
- Q: How is the system default device item displayed? → A: Just "System Default" without specifying the name of a specific device.
- Q: By which identifier should the selected device be saved between sessions? → A: Always use `kAudioDevicePropertyDeviceUID` (string) — a stable identifier across reboots.
- Q: What happens to an open dropdown menu when a device is connected/disconnected? → A: The dropdown closes, the list is updated the next time it is opened.
- Q: How to handle aggregate and virtual audio devices (BlackHole, Loopback, etc.)? → A: Show all input devices without filtering — anything that CoreAudio considers an input device is displayed in the list.
- Q: How to display devices with identical names (for example, two "USB Microphone")? → A: Show the name as is, allowing duplicates in the list. Internal identification by UID ensures correct operation.
- Q: At what sample rate should the WAV file be saved to disk? → A: At the device's native sample rate (without conversion) — maximum quality for archiving and diagnostics.
- Q: What to do with the WAV file when the sample rate changes on the same device (for example, A2DP→HFP)? → A: Close the current file and create a new one — similar to switching devices. Each WAV file contains a homogeneous audio stream.
- Q: What happens to active recording when the system default device is changed in macOS System Settings, if "System Default" is selected? → A: Recording restarts on the new default device (similar to manual switching). When saving to disk, a new file is created with the current timestamp and the name "System Default" in the file name.

## User Scenarios and Testing *(mandatory)*

### User Story 1 — Selecting an audio device from the floating window (Priority: P1)

The user opens the floating window for voice recording and sees the audio device selection menu. At the top of the list, separated by a visual divider, are the system default devices (System Default Input). Below the divider are all other available input devices, sorted alphabetically. The user selects the desired device, and it becomes active for the next recording.

**Why this priority**: This is the basic capability of the feature — without device selection, all other scenarios are impossible.

**Independent test**: Can be fully tested by opening the floating window, ensuring the device list is displayed correctly (system default on top, the rest alphabetically), and selecting a specific device.

**Acceptance scenarios**:

1. **Given** the floating window is open and several audio devices are connected to the computer, **When** the user opens the device selection menu, **Then** they see a list where system default devices are located at the top and separated by a horizontal line from the rest of the devices.
2. **Given** the floating window is open and several audio devices are connected to the computer, **When** the user views the list below the divider, **Then** the devices are sorted alphabetically.
3. **Given** the user has selected a specific device, **When** they start recording, **Then** the recording uses the selected device.
4. **Given** the user has selected a specific device, **When** they close and reopen the floating window, **Then** the device selection is preserved.

---

### User Story 2 — Correct work with Bluetooth devices (A2DP→HFP) (Priority: P1)

The user selects a Bluetooth device (for example, AirPods or Jabra) for recording. The system determines that this is a Bluetooth device and initiates the transition from the A2DP profile (playback, 48 kHz) to the HFP profile (recording). The system waits for the profile switch to complete, determines the actual sample rate (for example, 16 kHz or 24 kHz), and starts the audio engine specifically with this rate.

**Why this priority**: Bluetooth devices are one of the most common types of microphones among Mac users. Incorrect handling of profiles will result in no sound or distortion.

**Independent test**: Connect AirPods or another Bluetooth headset, select it in the floating window, start recording, and verify that the sound is recorded correctly.

**Acceptance scenarios**:

1. **Given** AirPods are connected in A2DP mode (48 kHz) and recording is not active, **When** the user selects them and starts recording, **Then** the system uses the unified method to check the current profile, detects A2DP, initiates switching to HFP, subscribes to OS events, waits for switch confirmation, determines the actual sample rate, and starts recording at that rate.
2. **Given** recording is already happening on the built-in microphone and the user switches the device to a Bluetooth headset, **When** the device change occurs, **Then** the system stops the current recording (data is lost), uses the same unified method to check the profile, switches to HFP if necessary, and automatically starts a new recording from scratch on the Bluetooth device.
3. **Given** a Jabra Bluetooth headset is connected, **When** the user starts recording, **Then** the system uses the unified method to correctly handle the A2DP→HFP transition and records sound without distortion.
4. **Given** a Bluetooth device switches between profiles, **When** the sample rate changes during recording, **Then** the system automatically restarts the audio engine with the new rate.
5. **Given** a Bluetooth device is already in HFP mode (for example, being used by another application), **When** the user starts recording, **Then** the unified method determines that the profile is already HFP, skips switching, and immediately starts recording.
6. **Given** recording is active on a Bluetooth device, **When** the user stops recording, **Then** the system initiates the device's return to the A2DP profile.
7. **Given** a Bluetooth device was disconnected during recording and then reconnected, **When** the user selects it again and starts recording, **Then** the system uses the same unified method to check the profile and perform A2DP→HFP switching.

---

### User Story 3 — Automatic fallback when a device is disconnected (Priority: P1)

The user records audio through a Bluetooth headset. The headset is disconnected (leaves the range, battery drains). The system detects the device's disappearance from the list, stops recording, shows the "Device disconnected" notification, and automatically switches the menu selection to the system default device. Recording does not continue automatically — the user must start it again manually.

**Why this priority**: Without automatic fallback, the user will be left with a "dead" device selection and will be unable to continue working.

**Independent test**: Start recording through a Bluetooth device, then disconnect it, and verify that the selection switched to the system default device.

**Acceptance scenarios**:

1. **Given** the user has selected a Bluetooth device and it disconnected (disappeared from the available list), **When** the system detects the device's disappearance, **Then** the menu selection automatically switches to the system default device.
2. **Given** the user has selected a USB microphone and it was physically disconnected, **When** the system detects the device's disappearance, **Then** the menu selection automatically switches to the system default device.
3. **Given** the default device is already selected and another device was disconnected, **When** the list is updated, **Then** the selection remains on the default device unchanged.

---

### User Story 4 — Handling recording start error (Priority: P2)

The user selects a device and presses the recording button, but the device is unavailable (for example, busy with another application or temporarily faulty). The system stops the recording attempt, displays the error message "Device unavailable", while in the selection menu the device remains selected (not reset to the default).

**Why this priority**: Correct error handling is important for the user experience, but it is a less likely scenario than the main device selection.

**Independent test**: Simulate a device unavailability situation and verify that the error is displayed and the device selection has not changed.

**Acceptance scenarios**:

1. **Given** the user has selected a device that is temporarily unavailable, **When** they press the recording button, **Then** recording does not start and the message "Device unavailable" is displayed.
2. **Given** a recording start error has occurred, **When** the user sees the error, **Then** the device in the selection menu remains selected (not reset).
3. **Given** a recording start error has occurred, **When** the user presses the recording button again, **Then** the system again attempts to start recording with the same device.

---

### User Story 5 — Sample rate validation before recording (Priority: P2)

Before starting recording, the system polls the selected device and determines its current sample rate (16,000, 24,000, 44,100, 48,000, 96,000 Hz and other values supported by the device). The audio engine starts strictly with the rate that the device actually provides, without forced conversion at the capture stage.

**Why this priority**: Sample rate mismatch leads to quiet sound, distortion, or complete audio loss. Important, but is part of internal mechanics, not direct user interaction.

**Independent test**: Connect devices with different sample rates, start recording with each, and verify the correctness of the sound.

**Acceptance scenarios**:

1. **Given** the device runs at 44,100 Hz, **When** the user starts recording, **Then** the audio engine starts at 44,100 Hz.
2. **Given** the Bluetooth device switched to HFP at 16,000 Hz, **When** the system determines the final rate, **Then** the audio engine starts at 16,000 Hz.
3. **Given** the device runs at a non-standard rate (for example, 96,000 Hz), **When** the user starts recording, **Then** the audio engine starts at that rate.

---

### User Story 6 — Diagnostic logging of device operations (Priority: P2)

All operations with audio devices are logged for diagnostic purposes: device selection, switching to the default device, recording start, errors. Each log entry contains the device identifier (device ID), device name, and at recording start — the sample rate used. On switches, both the previous and the new state are logged.

**Why this priority**: Logging is critically important for diagnosing user problems, but does not directly affect functionality.

**Independent test**: Perform device operations and verify that all necessary data is present in the logs.

**Acceptance scenarios**:

1. **Given** the user selects a device, **When** switching occurs, **Then** the log records: the old device (ID, name) and the new device (ID, name).
2. **Given** the user starts recording, **When** the audio engine starts, **Then** the log records: device ID, device name, sample rate used.
3. **Given** automatic fallback to the default device occurs, **When** the Bluetooth device disconnects, **Then** the log records: the reason for switching, the old and new device with their IDs and names.
4. **Given** a recording start error occurs, **When** the device is unavailable, **Then** the log records: device ID, device name, error code.
5. **Given** the user selects a Bluetooth device, **When** A2DP→HFP profile switching occurs, **Then** the log records: device ID, device name, original profile (A2DP) with sample rate, target profile (HFP) with sample rate, switching duration in milliseconds, final status (success/timeout/error).

---

### User Story 7 — Multiple sequential device switching (Priority: P1)

The user can sequentially change audio devices in any order: System Default → Bluetooth → AirPods → built-in microphone → Continuity → USB — and the system correctly handles each switch. This works both when recording is stopped (the menu selection simply changes) and during active recording. When the device is changed during recording, the current recording is stopped, previously recorded data is considered lost, and recording automatically starts from scratch on the new device.

**Why this priority**: Users often experiment with devices, connecting and switching them several times in a row. The system must work stably with any sequence of switches without accumulating errors.

**Independent test**: Sequentially switch devices 5+ times in different order (including Bluetooth devices), verify that each time the recording correctly starts on the new device.

**Acceptance scenarios**:

1. **Given** recording is not active, **When** the user sequentially changes devices (System Default → USB → Bluetooth → built-in), **Then** each switch correctly updates the menu selection without errors.
2. **Given** recording is active on a USB microphone, **When** the user switches to AirPods, **Then** the current recording stops, the previous recording data is lost, and recording automatically starts again on AirPods (with A2DP→HFP switching).
3. **Given** recording is active on AirPods, **When** the user quickly switches to the built-in microphone and then immediately to Continuity, **Then** each switch correctly stops the previous recording and starts a new one on the final device.
4. **Given** the user switched devices 5 times in a row during recording, **When** recording ends on the last selected device, **Then** the recorded data contains audio only from the last device.

---

### User Story 8 — Support for all device types (Priority: P3)

The system correctly displays and supports recording from all types of audio devices: built-in MacBook microphone, USB microphones, Bluetooth devices (AirPods, HFP headsets), Continuity devices (iPhone as a microphone via Continuity).

**Why this priority**: All device types are already supported via CoreAudio, but it is necessary to verify correct operation for each type.

**Independent test**: Connect one device of each type, select it, and record audio.

**Acceptance scenarios**:

1. **Given** the MacBook has a built-in microphone, **When** the user selects it, **Then** recording works correctly.
2. **Given** a USB microphone is connected, **When** the user selects it, **Then** recording works correctly.
3. **Given** an iPhone is connected via Continuity, **When** the user selects it as a microphone, **Then** recording works correctly.

---

### User Story 9 — Saving audio files during recording (Priority: P3)

The user can enable an option in Advanced Settings to save audio to disk during recording. By default, this feature is disabled. When enabled, the user selects a folder for saving via the standard system folder picker. Each recording is automatically saved to a file whose name contains the date, the time the recording started, and the name of the audio device. When the device is switched during recording, the current audio file is finalized, and a new file is created with the current device name.

**Why this priority**: An additional feature for advanced users, not critical for the main use case (voice input of text), but useful for debugging and archiving.

**Independent test**: Enable audio saving in settings, select a folder, start recording, verify that a file was created in the specified folder with the correct name. Switch the device during recording, verify that a second file was created.

**Acceptance scenarios**:

1. **Given** audio saving is disabled (by default), **When** the user records audio, **Then** no files are saved to disk (behavior as before).
2. **Given** the user enabled audio saving and selected the folder `~/Recordings`, **When** they start recording on the device "MacBook Pro Microphone" at 14:30:15 on March 20, 2026, **Then** the file `2026-03-20_14-30-15_MacBook Pro Microphone.wav` is created in the `~/Recordings` folder.
3. **Given** recording is active with saving to disk, **When** the user switches the device from "MacBook Pro Microphone" to "AirPods Pro", **Then** the current file is finalized and closed, and a new file `2026-03-20_14-32-00_AirPods Pro.wav` is created from the moment recording starts on the new device.
4. **Given** the user has not selected a folder for saving, **When** they see the toggle "Save audio recordings" in the settings, **Then** the toggle is disabled and cannot be enabled until a folder is selected.
5. **Given** the selected folder has become unavailable (deleted, unmounted), **When** the user starts recording, **Then** recording works normally (audio is sent to the API), but the file is not saved to disk, and the error is logged.
6. **Given** audio saving is enabled, **When** recording stops for any reason (Stop button, device disconnect, timeout), **Then** the current audio file is correctly finalized and closed.

---

### Edge cases

- What happens if all devices are disconnected except the built-in microphone? → The system default device (built-in microphone) is selected.
- What happens if the user selects a Bluetooth device and the transition to HFP hangs or takes too long? → The system waits no more than 5 seconds, after which it reports the error "Device unavailable".
- What happens if the device sample rate changes during recording (not just Bluetooth)? → The system automatically restarts the audio engine with the new rate.
- What happens if a device is connected and disconnected simultaneously? → The list is updated atomically, the selected device is checked for presence in the updated list.
- What happens if a Continuity device (iPhone) loses connection? → It is handled like a Bluetooth device disconnect: fallback to the system default device.
- What happens if the system default device is changed in System Settings? → The list is updated, the "System Default" item always points to the current device. If at that moment "System Default" is selected and recording is active — recording restarts on the new default device (similar to manual switching). When saving to disk, a new file is created with the current timestamp and the name "System Default".
- What happens if the user rapidly switches devices several times in a row (rapid switching)? → Each previous switch is correctly completed (the audio engine is stopped, resources are released) before the next one begins. The final recording uses the last selected device.
- What happens to recording data when the device is switched during active recording? → The previous recording data is considered lost. The new recording starts from scratch on the new device.
- What happens if the user switches from Bluetooth to Bluetooth (for example, from AirPods to Jabra)? → The system correctly ends the HFP session of the first device (with return to A2DP), calls the unified preparation method for the second device (A2DP→HFP switching), and starts recording with the new sample rate.
- What happens if the return to A2DP after stopping recording fails? → The error is logged but not shown to the user. The OS may return the profile by itself later.
- What happens if the Bluetooth device is already in HFP (used by another application)? → The unified method detects HFP via composite analysis (FR-035), skips switching, and immediately allows recording.
- What happens if during A2DP→HFP switching the device reports an intermediate incorrect sample rate? → The system performs debounce stabilization (FR-036): waits 300 ms, re-reads all three properties, repeats until stabilization or the overall timeout of 5 seconds.
- What happens if the device name contains characters not allowed in file names (for example, `/`, `:`)? → Invalid characters are replaced with `_` in the file name.
- What happens if there is not enough space on the disk to save the audio file? → Recording continues normally (audio is sent to the API), but the file is not saved to disk. An error is logged with the reason.
- What happens to the audio file when the application crashes during recording? → The file may be corrupted (incomplete); this is acceptable, as the feature is intended for diagnostics and archiving, not critical data storage.
- What happens if the user disables audio saving during active recording? → The current file is finalized and closed, subsequent recordings are not saved to disk.
- What happens if the user switches devices 5 times during a recording with saving enabled? → 5 separate audio files are created, one for each recording segment on each device.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST display audio device selection via the existing dropdown menu component (similar to the language selection menu) as a button inside the floating window summary.
- **FR-002**: The top of the list MUST contain exactly one item "System Default", separated by a horizontal divider from the other devices. The item is displayed without specifying the name of a specific device and always points to the current system default input device.
- **FR-003**: Devices below the divider MUST be sorted alphabetically.
- **FR-004**: The system MUST display all devices that CoreAudio classifies as input devices, without filtering by type (including aggregate and virtual devices). Explicitly supported types: built-in MacBook microphone, USB devices, Bluetooth devices (A2DP/HFP), Continuity devices (iPhone).
- **FR-005**: When a Bluetooth device is selected, preparation for recording MUST be performed via the unified method (FR-031/FR-032): (a) at recording start, if recording was not active; (b) immediately with full audio engine restart, if recording is already active at the moment of device change; (c) on reselection of the device after its reconnect. The system MUST wait for confirmation from the OS that the profile switching is complete and determine the actual sample rate.
- **FR-006**: The system MUST request the device's actual sample rate and start the audio engine strictly with that rate.
- **FR-007**: On recording start error, the system MUST stop the attempt, display the message "Device unavailable" (icon + text in the floating window, the standard error format of the application), and preserve the current device selection in the menu.
- **FR-008**: When the selected device disappears from the list, the system MUST stop the current recording (if active), show the "Device disconnected" message (icon + text in the floating window), and automatically switch the selection to the system default device. Recording MUST NOT continue automatically on the new device.
- **FR-009**: The device selection MUST be preserved between application sessions by the `kAudioDevicePropertyDeviceUID` identifier (string). At startup, if the saved device is unavailable, the system MUST silently (without notification) switch to System Default.
- **FR-010**: The device list MUST be updated dynamically when devices are connected/disconnected. If the dropdown menu is open at the moment of the list change, it MUST close; the updated list will be displayed on next opening.
- **FR-011**: On device switching (manual or automatic), the system MUST log the device ID and device name of both the old and the new device.
- **FR-012**: On recording start, the system MUST log the device ID, device name, and used sample rate. These fields MUST be present in all key audio engine events: format configuration, tap installation, recording start.
- **FR-013**: On device errors, the system MUST log the device ID, device name, and error code.
- **FR-014**: The system MUST wait for the completion of Bluetooth profile switching for no more than 5 seconds, after which it must show an error.
- **FR-015**: When the device sample rate changes during recording, the system MUST automatically restart the audio engine with the new rate.
- **FR-016**: On device change in the menu during active recording, the system MUST stop the current recording, discard previously recorded data, and automatically start recording from scratch on the new device. If recording is not active — it MUST only update the selection in the menu without any actions on the audio engine.
- **FR-017**: The system MUST support multiple sequential device switches in any order (including switches between different types: System Default, USB, Bluetooth, built-in, Continuity) without accumulating errors or resource leaks. Each switch MUST correctly finalize the previous operation before starting a new one.
- **FR-018**: If Bluetooth profile switching (A2DP→HFP) takes more than 200 ms, the system MUST show a spinner and the message "Switching…" in the popup window, and the Start/Stop button MUST be disabled until the switching is complete. If switching takes less than 200 ms — no additional UI is displayed.
- **FR-019**: When switching the Bluetooth profile A2DP→HFP, the system MUST log: device ID, device name, original profile and sample rate (A2DP), target profile and sample rate (HFP), actual switching duration in milliseconds, and final status (success/timeout/error).
- **FR-020**: Advanced Settings MUST contain the option "Save audio recordings to disk". By default, the option MUST be disabled.
- **FR-021**: When the audio saving option is enabled, the user MUST be able to select the destination folder via the standard system folder picker (NSOpenPanel). The selected path MUST be preserved between sessions.
- **FR-022**: During active recording with audio saving enabled, the system MUST write audio data to a WAV file in the selected folder. The audio MUST be saved at the device's native sample rate (without sample rate conversion).
- **FR-023**: The audio file name MUST be formed according to the template `YYYY-MM-DD_HH-mm-ss_<Device name>.wav`, where the date and time are the start time of recording on this device, and the device name is the display name of the current audio device. Characters not allowed in file names (`/`, `:`, `\`) MUST be replaced with `_`.
- **FR-024**: When the audio device is switched or the sample rate changes on the same device (for example, A2DP→HFP) during recording with saving enabled, the system MUST finalize and close the current audio file, then create a new file with a name containing the current time and the device name.
- **FR-025**: On recording stop (Stop button, device disconnect, timeout, error), the current audio file MUST be correctly finalized and closed.
- **FR-026**: If the selected folder is unavailable (deleted, unmounted, no write permissions), recording MUST continue normally (audio is sent to the API), but the file MUST NOT be saved to disk. The error MUST be logged.
- **FR-027**: If the folder for saving is not selected, the toggle "Save audio recordings" MUST be disabled. When opening the settings, if a previously saved bookmark is lost (folder deleted/unmounted), the toggle MUST be automatically reset to the disabled state.
- **FR-028**: RecordingViewModel MUST synchronize audio saving settings (`isAudioSaveEnabled`, `audioSaveFolderBookmark`) from AppSettings to AudioCaptureService before each call to `startRecording`. The AudioCaptureServiceProtocol protocol MUST include the property `audioSaveSettings`.
- **FR-029**: The diagnostic log "Ring buffer drain" MUST include the fields `deviceID` and `deviceName` of the current recording device.
- **FR-030**: When the system default input device (`kAudioHardwarePropertyDefaultInputDevice`) changes, the system MUST update the device list. If at that moment the "System Default" item is selected and recording is active, the system MUST restart recording on the new default device (similar to manual device switching per FR-016). When saving audio to disk, the file name MUST contain "System Default" as the device name and the timestamp of the start of the new recording.
- **FR-031**: The system MUST implement a single unified Bluetooth Profile Preparation method that is used in all three scenarios: (a) first start of recording on a Bluetooth device; (b) switching the device to Bluetooth during or outside recording; (c) reusing a Bluetooth device after its reconnect. Duplication of profile switching logic in different scenarios is NOT ALLOWED.
- **FR-032**: Bluetooth device preparation for recording MUST be performed in two stages: (1) `BluetoothProfileManager.prepareForRecording` determines the current profile (A2DP/HFP) and returns the result instantly; (2) `AudioCaptureService.startRecording(awaitBluetoothSwitch: true)` for ALL BT devices (including already-HFP, since rate may be stale after A2DP restore): (a) starts the engine without a tap (triggers A2DP→HFP at the OS level); (b) subscribes to `kAudioDevicePropertyNominalSampleRate` and waits for rate stabilization ≤24kHz with debounce of 300ms; (c) stops the trigger engine; (d) starts a fresh engine with a tap and file writing at the stabilized rate. The total timeout is 5 seconds (FR-014). **Note**: `already_hfp` does not guarantee rate freshness — after A2DP restore CoreAudio may return a stale value. Therefore stabilization is mandatory for ALL BT devices.
- **FR-033**: After stopping recording on a Bluetooth device, the system MUST initiate the device's return to the A2DP profile (high-quality playback). A failure to return to A2DP MUST NOT affect the user (silent logging).
- **FR-034**: The unified Bluetooth device preparation method MUST log at each stage: (a) call context — one of the values: `first_start`, `device_switch`, `reconnect`; (b) the current device profile status before preparation begins (A2DP/HFP/unknown); (c) the decision about the need for switching (skip/required); (d) the fact of subscription to OS events; (e) receipt of confirmation from the OS with details (new sample rate, waiting time); (f) the final result (success/timeout/error). On return to A2DP after stopping recording — log: device ID, device name, return result (success/error).
- **FR-035**: Determining the current Bluetooth profile MUST be performed by `kAudioDevicePropertyNominalSampleRate` — sample rate ≤24 kHz = HFP, ≥44.1 kHz = A2DP. The property `kAudioDevicePropertyTransportType` MUST be used as a filter: the analysis applies ONLY to Bluetooth devices. **Note**: input channels MUST NOT be used as a profile criterion — for input-only BT devices (Loopback, aggregate) `inputChannels > 0` always, regardless of the profile. Sample rate is the only reliable criterion.
- **FR-036**: When waiting for BT rate stabilization, the system MUST: (a) 300ms after engine start, check the current rate — if ≤24kHz, consider it stable (already HFP); (b) on receiving notification about a change of `kAudioDevicePropertyNominalSampleRate` — accept ONLY rates ≤24kHz (HFP-range), ignoring false triggers at 48kHz (A2DP) caused by engine setup; (c) after receiving the HFP rate — debounce 300ms and confirm that the rate is still ≤24kHz; (d) total timeout is 5 seconds (FR-014), on timeout use the current rate.
- **FR-037**: BT rate stabilization is performed in `AudioCaptureService` (not in `BluetoothProfileManager`), since it requires a running engine to trigger switching. `BluetoothProfileManager` is responsible only for profile detection.
- **FR-038**: When restarting the audio engine on the sample rate change notification (FR-015), the system MUST ignore false triggers: if the device's actual sample rate has not changed, the restart MUST NOT be performed. The system MUST store `lastKnownSampleRate` and compare on each notification.
- **FR-039**: On an audio engine startup error on the selected device with fallback to the system default device, the system MUST notify the UI layer via the `onDeviceFallback` callback and perform a full switch to System Default via the standard flow (`switchAudioDevice`), including updating `selectedDevice`, resetting the recording, and restarting.
- **FR-040**: For ALL Bluetooth devices (including those detected as `already_hfp`), the system MUST use two-phase startup: (1) engine without a tap to trigger and stabilize the rate; (2) fresh engine with a tap at the stabilized rate. This prevents the format mismatch crash, when `deviceNominalSampleRate` returns a stale value after A2DP restore, and the actual hardware rate is different. The stabilization MUST accept only HFP-range rate (≤24kHz), ignoring false A2DP notifications from engine setup.

### Key Entities

- **Audio Device**: Represents an audio input device. Key attributes: unique identifier, display name, type (built-in, USB, Bluetooth, Continuity), current sample rate, whether it is the default device.
- **Bluetooth Profile**: The operating mode of a Bluetooth device. A2DP — the high-quality playback profile (48 kHz, does not support recording), HFP — the hands-free profile (16–24 kHz, supports recording).
- **System Default**: The device selected in macOS System Settings as the default input device. Used as a fallback when the selected device is disconnected.
- **Audio Recording File**: A WAV file saved to disk when the saving option is enabled. Key attributes: file path, name (date + time + device), duration, sample rate.

## Success Criteria *(mandatory)*

### Measurable outcomes

- **SC-001**: The user can select any connected audio device and start recording in no more than 3 actions (open menu → select device → press record).
- **SC-002**: When a Bluetooth device is disconnected, the system switches to the default device within 2 seconds.
- **SC-003**: Recording through a Bluetooth device (with A2DP→HFP switching) starts within 5 seconds from the moment the record button is pressed.
- **SC-004**: Each device operation (selection, switching, start, error) contains in the log the device ID, device name, and at start — the sample rate. Bluetooth A2DP→HFP switching additionally contains: source/target profile, sample rate before and after, switching duration in milliseconds, final status.
- **SC-005**: The system works correctly with all four types of devices: built-in, USB, Bluetooth, Continuity.
- **SC-006**: On a recording start error, the user sees a clear error message, and the device selection is not reset.
- **SC-007**: The system withstands 5+ sequential device switches (in any order of types) without errors, resource leaks, or performance degradation.
- **SC-008**: When the device is switched during recording, a new recording on the new device starts within 5 seconds (including Bluetooth A2DP→HFP switching).
- **SC-009**: With audio saving enabled, each recording creates a file in the selected folder with the correct name (date + time + device) in WAV format.
- **SC-010**: When the device is switched during recording with saving enabled, a separate file is created for each segment with the correct device name.
- **SC-011**: The unavailability of the save folder does not block the main recording functionality (audio continues to be sent to the API).
- **SC-012**: The single unified Bluetooth device preparation method is used in all three scenarios (first start, device change, reconnect) — the codebase does not contain duplicated A2DP→HFP switching logic.
- **SC-013**: Each call to the unified Bluetooth preparation method contains in the log: call context, profile status before/after, switching decision, OS confirmation wait time, final result.
- **SC-014**: After stopping recording on a Bluetooth device, the profile returns to A2DP. A return failure does not affect the application's operation.

## Assumptions

- The system uses CoreAudio to enumerate devices and determine their characteristics (sample rate, connection type), as this is the standard approach for macOS applications.
- The waiting time for Bluetooth profile switching (5 seconds) is a reasonable value based on the current implementation in the project.
- Continuity devices (iPhone) are handled by CoreAudio similarly to regular audio devices after the connection is established.
- "System default device" corresponds to `kAudioHardwarePropertyDefaultInputDevice` in CoreAudio terminology.
- Audio files are saved in WAV (PCM) format, as this is the standard uncompressed format compatible with any audio editor.
- The path to the save folder is stored via Security-Scoped Bookmarks (for access outside App Sandbox after application restart).
- Saving audio to disk is an additional feature, not critical for the main flow (voice input); disk write errors do not interrupt the main recording.

## Dependencies

- Feature 008 (Fix Async Concurrency) — Bluetooth event handling and lock-free audio capture architecture.
- Feature 007 (Diagnostic Logging) — diagnostic logging system through which all device events are recorded.
- Feature 005 (Recording Window Redesign) — current design of the floating window in which the device selection menu is placed.
