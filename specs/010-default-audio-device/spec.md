# Feature Specification: Default Audio Device in Settings

**Branch**: `010-default-audio-device`
**Created**: 2026-03-21
**Status**: Draft
**Input**: User description: "Selection of default audio device in application settings. Filtering of macOS system aggregate devices (CADefaultDeviceAggregate). When the floating window opens, the device is loaded from settings; during a session it can be temporarily switched; on reopening — again from settings. Stable device ID across reboots. Automatic fallback to System Default when the saved device disappears."

## User Scenarios and Testing *(required)*

### User Story 1 — Selecting the Default Device in Settings (Priority: P1)

The user opens the application settings and in the "Recording" section sees a Picker for selecting the default audio device. The first item in the list is "System Default", followed by all available input devices in alphabetical order. macOS system aggregate devices (CADefaultDeviceAggregate) are hidden from the list. The user picks the desired device, and the choice is persisted across application launches.

**Why this priority**: A basic capability — to set the default device from the settings UI.

**Independent test**: Open settings → choose a device → restart the application → confirm the choice is preserved.

**Acceptance scenarios**:

1. **Given** settings are open and several devices are connected, **When** the user opens the audio device Picker, **Then** they see "System Default" as the first item and the remaining devices in alphabetical order, without CADefaultDeviceAggregate.
2. **Given** the user has selected a specific device, **When** they close and reopen settings, **Then** the selected device is shown as the current choice.
3. **Given** the user has selected a specific device, **When** they restart the application, **Then** the device selection is preserved.

---

### User Story 2 — Loading the Device into the Floating Window on Open (Priority: P1)

When the floating recording window opens (via hotkey), the system loads the device specified as the default in settings. This device becomes active in the floating window's dropdown and is used for recording.

**Why this priority**: Without it, the link between settings and the floating window does not work.

**Independent test**: Set the device in settings → open the floating window → confirm the dropdown shows the selected device.

**Acceptance scenarios**:

1. **Given** "USB Microphone" is selected in settings, **When** the user opens the floating window via hotkey, **Then** the audio device dropdown shows "USB Microphone".
2. **Given** "System Default" is selected in settings, **When** the user opens the floating window, **Then** the dropdown shows "System Default".

---

### User Story 3 — Temporary Device Switch in the Floating Window Session (Priority: P1)

During a floating window session, the user can switch the audio device through the dropdown. This change applies only to the current session. When the floating window is closed and reopened, the device is reset to the value from settings.

**Why this priority**: Allows quickly switching to a different microphone without changing the default settings.

**Independent test**: Set device A in settings → open the window (shows A) → switch to B → close the window → open again → shows A.

**Acceptance scenarios**:

1. **Given** device A is selected in settings and the floating window is open with device A, **When** the user switches to device B in the dropdown, **Then** recording uses device B.
2. **Given** the user has switched to device B in the current session, **When** they close the floating window and open it again, **Then** the dropdown shows device A (from settings).
3. **Given** the user has switched the device in the floating window, **When** they check settings, **Then** the value in settings has NOT changed (still device A).

---

### User Story 4 — Automatic Fallback When the Device Disappears (Priority: P2)

If the device specified as the default in settings is disconnected (Bluetooth off, USB removed), the system automatically resets the value in settings to "System Default". In the floating window, if it is open, the device also switches to System Default.

**Why this priority**: Ensures functionality remains when hardware configuration changes.

**Independent test**: Set BT headphones → disconnect BT → check settings and the floating window.

**Acceptance scenarios**:

1. **Given** BT headphones are selected in settings and the floating window is closed, **When** the BT headphones are disconnected, **Then** the value in settings automatically changes to "System Default".
2. **Given** BT headphones are selected in settings and the floating window is open, **When** the BT headphones are disconnected, **Then** the dropdown switches to "System Default", and recording (if active) is handled in the standard way (stop + notification).
3. **Given** BT headphones were disconnected and settings reset to System Default, **When** the BT headphones are reconnected, **Then** settings remain on System Default (no automatic return).

---

### User Story 5 — Filtering System Aggregate Devices (Priority: P2)

macOS system aggregate devices (with names starting with `CADefaultDeviceAggregate`) are hidden from all selection lists: both in settings and in the floating window. These devices are an internal macOS implementation detail and should not be visible to the user.

**Why this priority**: Improves UX — the user does not see obscure technical devices.

**Independent test**: Verify that under any device configuration CADefaultDeviceAggregate does not appear in any list.

**Acceptance scenarios**:

1. **Given** macOS has created the aggregate device CADefaultDeviceAggregate, **When** the user opens the Picker in settings, **Then** this device is not displayed.
2. **Given** macOS has created the aggregate device CADefaultDeviceAggregate, **When** the user opens the dropdown in the floating window, **Then** this device is not displayed.

---

### Edge Cases

- What happens at application startup if the saved device is unavailable? → Silent fallback to System Default, without notification.
- What if the user selected System Default in settings and the system default device changed? → Nothing — System Default always points to the current system device.
- What if two devices have the same name? → Both are displayed; internal identification by stable UID.
- What if the floating window is open and the device from settings is connected? → Nothing — the current session keeps its own selection.

## Requirements *(required)*

### Functional Requirements

- **FR-001**: The application settings ("Recording" section) MUST contain a Picker for selecting the default audio device.
- **FR-002**: The Picker in settings MUST display "System Default" as the first item, followed by all available input devices in alphabetical order.
- **FR-003**: Devices whose name starts with `CADefaultDeviceAggregate` MUST be hidden from all selection lists (settings and floating window).
- **FR-004**: The device selection in settings MUST persist across application launches by the `kAudioDevicePropertyDeviceUID` identifier — a stable string that does not depend on OS or application restart.
- **FR-005**: When the floating window opens, the system MUST load the device from settings (the default device) and set it as the active one in the dropdown.
- **FR-006**: During a floating window session, the user MAY switch the device via the dropdown. This change MUST NOT alter the default device value in settings.
- **FR-007**: When the floating window is closed and reopened, the device MUST be loaded again from settings (resetting the temporary selection).
- **FR-008**: If the device specified as the default in settings disappears from the list of available devices (disconnect), the system MUST automatically reset the value in settings to "System Default".
- **FR-009**: When a device is chosen in the settings Picker, the system MUST synchronize the choice with the device manager so that the floating window (if open) reflects the change.
- **FR-010**: When the floating window opens, if the saved device is unavailable, the system MUST silently (without notification) use System Default.
- **FR-011**: The list of devices in settings MUST update dynamically when devices are connected/disconnected (hot-plug).

### Key Entities

- **Default Audio Device**: The audio device selected by the user in settings. Used as the initial value each time the floating window opens. Identified by a stable UID (`kAudioDevicePropertyDeviceUID`). Empty string = System Default.
- **Session Audio Device**: The device active in the current floating window session. May differ from the default device. Reset when the window is closed.

## Success Criteria *(required)*

### Measurable Outcomes

- **SC-001**: The user can set the default device in settings within 2 actions (open the Picker, choose a device), and the choice persists across restarts.
- **SC-002**: When the floating window opens, the device from settings is loaded in under 300 ms.
- **SC-003**: A temporary device change in the floating window does not modify the value in settings — verified by closing and reopening the window.
- **SC-004**: When the saved device is disconnected, the system automatically switches to System Default within 2 seconds.
- **SC-005**: System aggregate devices (CADefaultDeviceAggregate) are not displayed in any selection list.
- **SC-006**: The device identifier remains stable after OS reboot — the same physical microphone is selected automatically.
- **SC-007**: Operation with 5+ devices simultaneously without UX degradation.

## Assumptions

- The existing infrastructure from 009-audio-device-selector (`AudioDeviceManager`, `AudioDevice`, `CoreAudioDeviceProvider`, `MicrophoneSelectorButton`) is reused.
- `kAudioDevicePropertyDeviceUID` is already used as the stable identifier in `AppSettings.selectedAudioDeviceUID`.
- Filtering of CADefaultDeviceAggregate is already partially implemented in `CoreAudioDeviceProvider.enumerateInputDevices()`.
- Hot-plug listeners are already implemented in `AudioDeviceManager`.

## Dependencies

- **009-audio-device-selector**: Reuses models, services, and UI components from this feature.

