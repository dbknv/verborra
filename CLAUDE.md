# spec-kit

Toolkit for Spec-Driven Development (SDD) with AI assistants.

> **Human-readable docs:** [docs/index.md](docs/index.md) | [docs/quickstart.md](docs/quickstart.md)

## Workflow Overview

```
specify → clarify → plan → [ui] → tasks → implement → verify → fix
   │         │        │      │       │         │          │       │
   ▼         ▼        ▼      ▼       ▼         ▼          ▼       ▼
spec.md  questions  plan.md ui/*.md tasks.md  code     issues   fixes
                    research.md              tests     report
                    data-model.md
                    contracts/

UI branch (optional):  implement-ui → verify-ui → fix
                            │             │
                            ▼             ▼
                       styled UI    UI issues
```

**Alternative entry:** `synthesize` — merge multiple existing documents into spec.

## Commands Quick Reference

| Command                  | Purpose                               | Next Step          |
| ------------------------ | ------------------------------------- | ------------------ |
| `/speckit.specify`       | Create feature spec from description  | → plan, clarify    |
| `/speckit.synthesize`    | Merge multiple docs into spec         | → plan, clarify    |
| `/speckit.clarify`       | Ask clarifying questions, update spec | → specify          |
| `/speckit.plan`          | Generate technical plan + research    | → tasks, checklist |
| `/speckit.tasks`         | Break plan into actionable tasks      | → implement        |
| `/speckit.implement`     | Execute tasks from tasks.md (logic)   | → verify           |
| `/speckit.implement-ui`  | Style UI components per Figma specs   | → verify-ui        |
| `/speckit.verify`        | Verify logic implementation           | → fix              |
| `/speckit.verify-ui`     | Verify UI against specifications      | → fix              |
| `/speckit.fix`           | Fix detected issues                   | → verify           |
| `/speckit.analyze`       | Cross-artifact consistency check      | -                  |
| `/speckit.checklist`     | Generate domain-specific checklist    | -                  |
| `/speckit.constitution`  | Create/update project constitution    | -                  |
| `/speckit.taskstoissues` | Convert tasks to GitHub issues        | -                  |
| `/speckit.ui`            | Generate UI spec from Figma           | → tasks            |
| `/speckit.ui-synthesize` | Synthesize UI specifications          | → tasks            |

## Agents (GitHub Copilot)

| Agent                 | Trigger         | Purpose                                 |
| --------------------- | --------------- | --------------------------------------- |
| `speckit.verify`      | After implement | Verify [X] tasks against spec/contracts |
| `speckit.fix`         | After verify    | Fix detected issues                     |
| `speckit.integration` | CI/CD           | Integration checks                      |

## Scripts API

All scripts support `--json` flag for structured output. Available in Bash and PowerShell versions.

```bash
# Check prerequisites, get feature paths
.specify/scripts/bash/check-prerequisites.sh --json [--require-tasks] [--include-tasks]

# Parse tasks.md, filter by status
.specify/scripts/bash/parse-tasks.sh --feature-dir <path> --status completed --json

# Parse synthesize source arguments
.specify/scripts/bash/parse-sources.sh <sources...> --json --max-sources 10

# Setup synthesize environment
.specify/scripts/bash/synthesize-setup.sh --feature-name <name> --sources-json <json>

# Cache source-of-truth files
.specify/scripts/bash/cache-sot.sh --feature-dir <path> --json

# Check contracts compliance
.specify/scripts/bash/contract-check.sh --feature-dir <path> --json

# Get file signatures for change detection
.specify/scripts/bash/file-signatures.sh --files <paths> --json

# Validate UI specifications
.specify/scripts/bash/validate-ui-specs.sh --ui-dir <path> --json
```

## Directory Structure

```
project/
├── .claude/commands/           # Slash commands (speckit.*.md)
├── .github/agents/             # Copilot agents (speckit.*.agent.md)
├── .specify/
│   ├── memory/                 # Project memory (constitution.md)
│   ├── scripts/
│   │   ├── bash/               # Utility scripts (JSON API)
│   │   ├── powershell/         # PowerShell versions
│   │   └── tests/              # Script tests
│   └── templates/              # Document templates
├── specs/
│   └── NNN-feature-name/       # Feature specs
│       ├── spec.md
│       ├── plan.md
│       ├── tasks.md
│       ├── research.md
│       ├── data-model.md
│       ├── quickstart.md
│       ├── contracts/
│       ├── checklists/
│       ├── ui/
│       └── verification/
└── docs/                       # Documentation
```

## Conventions

1. **Language**: Output docs in English, source artifacts in English
2. **Paths**: Always use absolute paths in scripts
3. **IPC**: JSON between scripts (`--json` flag)
4. **Branch naming**: `NNN-short-name` (e.g., `005-user-auth`)
5. **Task status**: `[ ]` pending, `[X]` completed
6. **Risk levels**: `[critical]`, `[high]`, `[medium]`, `[low]`

## Key Files

| File                     | Purpose                                            |
| ------------------------ | -------------------------------------------------- |
| `constitution.md`        | Project principles (TDD, tech stack, constraints)  |
| `spec.md`                | Feature specification (user stories, requirements) |
| `plan.md`                | Technical implementation plan                      |
| `tasks.md`               | Actionable tasks with risk levels                  |
| `research.md`            | Technical decisions and rationale                  |
| `data-model.md`          | Database schema, entities                          |
| `contracts/`             | API specifications (OpenAPI, GraphQL)              |
| `ui/*.md`                | UI component specifications (from Figma)           |
| `verification/issues.md` | Found issues during verification                   |
| `verification/report.md` | Final verification report                          |

## Command Mechanics

### /speckit.synthesize

Merge multiple documents into unified spec using Voice Weight Algorithm:

```bash
/speckit.synthesize requirements.md:9 notes.md:5 brainstorm.md:2 --verbose
```

**Syntax:** `path:weight[:order]` where weight = 1-10, order = load priority.

**Algorithm:** `Effective Weight = Explicit Weight × Significance Score (0.0-1.0)`

| Phase | Action                                                     | Script                |
| ----- | ---------------------------------------------------------- | --------------------- |
| 0     | Parse sources (path:W:O, folders, globs)                   | `parse-sources.sh`    |
| 1     | Load & score significance                                  | LLM                   |
| 2     | Detect conflicts, resolve by effective weight (Multi-Lens) | LLM                   |
| 3     | Create branch, setup directories                           | `synthesize-setup.sh` |
| 4-5   | Generate spec, validate                                    | LLM                   |

**Reliability:** ✅ Graceful degradation, ✅ Checkpoint system (`--save-checkpoint`/`--checkpoint`), ✅ Dry-run mode

### /speckit.verify

Risk-based verification of completed tasks:

| Risk     | Markers                                    | Level       | Confidence |
| -------- | ------------------------------------------ | ----------- | ---------- |
| CRITICAL | `critical path`, `security`, `auth`, `pii` | L4 Deep     | 95%        |
| STANDARD | All other tasks                            | L2 Standard | 80%        |

**Options:** `--deep` (L4 for all), `--full` (ignore cache), `--recheck V001`, `story:US3`

**Flow:** Parse tasks → Load MCP Memory → Classify risk → Execute checks with streaming → Create issues (V001...) → Update markers

### /speckit.ui

Generate UI component specs from spec.md + Figma URLs:

```text
/speckit.ui
https://figma.com/file/ABC123 — US1: login form
  fields: email (required), password (required)
  state: default
```

**Source of Truth Priority:**

1. Expert description → Structure + Behavior (always available)
2. spec.md → Acceptance Criteria (always available)
3. Figma MCP → Visual Details (may be unavailable)

**Output:** `ui/*.md` with Props Interface, States, Behavior, Accessibility, Dependencies

### /speckit.ui-synthesize

Create UI specs from prepared ui-analysis.md:

```bash
/speckit.ui-synthesize --context ui-analysis.md:9 --figma "URL" --output specs/008/ui/
```

Uses Voice Weight from synthesize, outputs same format as `/speckit.ui`.

## UI Specs Integration

**All core commands** understand UI specifications from `FEATURE_DIR/ui/*.md`:

| Command                 | UI Spec Usage                                            |
| ----------------------- | -------------------------------------------------------- |
| `/speckit.tasks`        | Generates tasks per component (Type → task count)        |
| `/speckit.implement`    | Loads Props, States, Behavior → generates component code |
| `/speckit.implement-ui` | Styles components per Figma specs (colors, spacing, etc) |
| `/speckit.verify`       | Verifies logic against spec.md and contracts             |
| `/speckit.verify-ui`    | Verifies UI against ui/\*.md specs                       |

**Validation:** `.specify/scripts/bash/validate-ui-specs.sh --ui-dir <path> --strict --json`

**Markers:**

- `[TODO]` — requires human review (blocks `--strict`)
- `[VISUAL_TODO]` — visual details not obtained from Figma
- `[MCP_UNAVAILABLE]` — Figma MCP was unavailable
- `[NEEDS JUSTIFICATION]` — deviation from design system

## Context7 Library IDs

| Technology | Library ID |
| ---------- | ------------------------------------------ |
| Node.js    | `/websites/nodejs_latest-v24_x_api`        |
| PostgreSQL | `/postgres/postgres`                       |
| shadcn/ui  | `/websites/ui_shadcn`                      |
| Docker     | `/docker/docs`                             |
| GitLab CI  | `/gitlab_gitlab-org/gitlab`                |

Use with `get-library-docs` tool or ask: *"Find Node.js v24 documentation via context7"*

## Error Handling

- Scripts return non-zero exit code on failure
- JSON output includes `success: false` and `error` field
- Verify agent logs issues with severity: critical > high > medium > low

## Active Technologies
- SwiftUI, AppKit (NSPanel), AVFoundation (AVAudioEngine), Security (Keychain), ServiceManagement (SMAppService), swift-markdown (swiftlang), KeyboardShortcuts (sindresorhus) (001-voice-input)
- UserDefaults (simple settings), macOS Keychain (API key), JSON in Application Support (named prompts) (001-voice-input)
- Swift 5.9+ + SwiftUI, AVFoundation (AVCaptureDevice), AppKit (AXIsProcessTrusted, NSWorkspace), Observation framework (004-permissions-rework)
- UserDefaults / @AppStorage (settings), macOS Keychain (API key) (004-permissions-rework)
- Swift 5.9+ (Xcode 15+) + SwiftUI, AppKit (NSPanel, NSWindow, NSAlert), AVFoundation (AVCaptureDevice), Accessibility API (AXIsProcessTrusted) (004-permissions-rework)
- Swift 5.9+ (Xcode 15+) + os.Logger (Unified Logging System), Foundation (FileHandle, DispatchQueue) (007-diagnostic-logging)
- JSONL files in ~/Library/Application Support/Verborra/Logs/; UserDefaults for level configuration (007-diagnostic-logging)
- Swift 5.9+ (Xcode 15+) + AVFoundation (AVAudioEngine), CoreAudio (AudioObjectPropertyListenerBlock), swift-atomics (NEW — apple/swift-atomics 1.2.0+), swift-markdown (0.4.0+), KeyboardShortcuts (2.0.0+) (008-fix-async-concurrency)
- N/A (in-memory audio buffers, UserDefaults for settings) (008-fix-async-concurrency)
- Swift 5.9+ (Xcode 15+) + SwiftUI, AVFoundation, swift-markdown (0.4.0+), KeyboardShortcuts (2.0.0+), swift-atomics (1.2.0+) (012-vocabularies)
- JSON files in `~/Library/Application Support/Verborra/` (vocabularies.json); UserDefaults / @AppStorage (personal preferences text) (012-vocabularies)
- Swift 5.9+ (Xcode 15+) + SwiftUI, AppKit (NSPanel, NSAlert), AVFoundation (AVAudioEngine — уже используется), swift-markdown (4.0+ — уже используется для рендеринга), KeyboardShortcuts (sindresorhus — уже используется), swift-atomics (1.2+ — уже используется в стриминге) (013-dictation-flow-rework)
- JSON файл `~/Library/Application Support/Verborra/system_prompts.json` (через существующий `PromptsStore`); UserDefaults для `promptsDataVersion` (013-dictation-flow-rework)
- Swift 5.9+ (Xcode 15+) + SwiftUI, AppKit (NSPanel), AVFoundation (AVAudioEngine), swift-markdown (4.0+), KeyboardShortcuts (sindresorhus), swift-atomics (1.2+) — all already in the project; no additions. (014-voice-level-and-language)
- UserDefaults / `@AppStorage` (Settings default for response language — existing `AppSettings.globalTextLanguage`). The floating-window override is in-memory only on `RecordingViewModel`. The new structured language-resolution event is logged via the existing JSONL diagnostic logging system (spec 007, `~/Library/Application Support/Verborra/Logs/`). (014-voice-level-and-language)

## Recent Changes
- 001-voice-input: Added SwiftUI, AppKit (NSPanel), AVFoundation (AVAudioEngine), Security (Keychain), ServiceManagement (SMAppService), swift-markdown (swiftlang), KeyboardShortcuts (sindresorhus)
