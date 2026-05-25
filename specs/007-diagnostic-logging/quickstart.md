# Quickstart: Diagnostic Logging

**Feature**: 007-diagnostic-logging
**Date**: 2026-03-19

## Quick verification

### Scenario 1: Basic logging (US6)

1. Launch the application
2. Open Console.app, filter: subsystem = `dev.apeek.verborra`
3. Make sure INFO lifecycle messages are visible in Console.app:
   `"Application launched"`, session ID
4. Open `~/Library/Application Support/Verborra/Logs/`
5. Make sure a JSONL file named `verborra-YYYY-MM-DDTHH.jsonl` is created
6. Read the first line of the file — a valid JSON with fields:
   `timestamp`, `level`, `category`, `sessionId`, `message`

**Expected result**: logs are written simultaneously to Console.app and the JSONL file.

### Scenario 2: Audio device logging (US1)

1. Launch the application (INFO level)
2. Connect a Bluetooth device (AirPods)
3. In Console.app: filter category = `audio` or `bluetooth`
4. Make sure the log contains: device name, type, connection status
5. Select the Bluetooth device as the microphone
6. Make sure the log contains: name, ID, type, switching result
7. Switch the level to DEBUG in settings
8. Repeat — make sure the log shows sample rate, channels, format

**Expected result**: all audio events are logged with correct markers.

### Scenario 3: API request logging (US2)

1. Launch the application (INFO level)
2. Record audio and wait for transcription
3. In the JSONL file: find records with category = `api`
4. Verify: URL, HTTP method, payload size, status, execution time
5. Switch to DEBUG
6. Repeat — make sure the log additionally contains:
   headers (without API key), request body, response body
7. Verify that the API key is masked (`sk-...XXXX`)

**Expected result**: API requests are fully logged; secrets are masked.

### Scenario 4: ERROR with context (US5)

1. Start recording
2. Disconnect the Bluetooth device during recording (failure simulation)
3. In the JSONL file: find an entry with `"level":"ERROR"`
4. Check the presence of:
   - `error.description` — what broke
   - `error.breadcrumbs` — chain of preceding actions
   - `error.state` — device, recording status, duration
   - `error.errorCode` — error type
5. Make sure the cause of the failure can be understood from a single ERROR message

**Expected result**: a self-sufficient ERROR message with full context.

### Scenario 5: Level management (US6)

1. Open Settings → Advanced
2. Verify: Picker with options OFF / ERROR / INFO / DEBUG
3. Verify: the "Show logs in Finder" link opens the logs directory
4. Switch to DEBUG → make sure DEBUG messages are written immediately
5. Switch to OFF → make sure logs stop
6. Start recording, switch to OFF → make sure OFF
   is deferred until recording completes

**Expected result**: the level changes without restart.

### Scenario 6: Rotation and cleanup (US6)

1. Launch the application with DEBUG (many records)
2. Wait for the hour to change or create a file > 50 MB
3. Verify that a new file with a new name is created
4. Manually create a file in the logs directory with a date > 24 hours ago
5. Restart the application
6. Verify that the old file has been deleted

**Expected result**: rotation by time/size; cleanup by age.

### Scenario 7: Permissions (US3)

1. Revoke microphone permission in System Settings
2. Try to start recording
3. In JSONL: find an entry with category = `permissions`
4. Verify: error "access denied", call context

**Expected result**: permission denials are logged.

### Scenario 8: User actions (US4)

1. Press the global hotkey
2. Select a prompt, start recording, change the language
3. In JSONL: find entries with category = `userAction`
4. Verify: each action is recorded with a timestamp

**Expected result**: full user action trace.

## Security checklist

- [ ] API key never appears in logs in plain form
- [ ] User's recognized text is not logged
- [ ] Audio buffer contents are not logged (only metadata)
- [ ] In os_log sensitive data is marked `.private`
