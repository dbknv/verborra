---
description: Verify UI component implementation against ui/*.md specs, Figma sources, and design system
handoffs:
  - label: Fix UI issues
    agent: speckit.fix
    prompt: Fix all detected UI issues
    send: true
---

## User Input

```text
$ARGUMENTS
```

**Supported arguments:**

- `--component ComponentName` — Verify specific component
- `--deep` — Full visual + accessibility audit
- `--recheck V042` — Re-verify specific UI issue
- `--skip-graph` — Skip graph connectivity check

## Language

All **produced project documentation** (new files you create or updates you write into markdown docs) MUST be written in **Russian**.

Source operational artifacts MUST remain in English:

- Commands (`.claude/commands/**`)
- Memory (`.specify/memory/**`)
- Document templates (`.specify/templates/**`)

## Outline

1. **Load Prerequisites**
   Run `.specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks` from repo root.
   Parse FEATURE_DIR and SRC_DIR. All paths must be absolute.

2. **UI Graph Connectivity Check**
   **Skip if**: `--skip-graph` flag provided.

   Run graph-check.sh with ui-extras mode to detect UI-specific dead code:

   ```bash
   .specify/scripts/bash/graph-check.sh "$FEATURE_DIR" "$SRC_DIR" --mode=ui-extras
   ```

   Parse JSON output. UI-specific check:
   - `graph_missing_trigger` — modal/popup without useState trigger (severity: **critical**)

   **Note**: Basic checks (unused_export, imported_not_used) are handled by `speckit.verify`.
   This command adds UI-specific modal/popup trigger verification.

   Create issues for each finding.

3. **Discover UI Components**

   **Method A (Preferred)**: Parse tasks with UI filter:

   ```bash
   .specify/scripts/bash/parse-tasks.sh --feature-dir "$FEATURE_DIR" --filter "[UI]" --status completed
   ```

   For each UI task:
   1. Extract component name from task description
   2. Find corresponding `ui/{Component}.md`
   3. Resolve implementation file path via:
      a) ui/\*.md **Path** field in Props/Implementation section (preferred)
      b) `find "$SRC_DIR" -name "{Component}.tsx"`
      c) If multiple matches → ask user to clarify

   **Method B (Fallback)**: If no tasks with [UI] marker:

   ```bash
   find "$FEATURE_DIR/ui" -name "*.md" -type f 2>/dev/null
   ```

   Build list: `[(component_file, ui_spec_file), ...]`

   For each ui spec, also extract:
   - Figma references (from "Figma References" section) for visual verification

4. **Verify Each UI Component**
   For each ui/\*.md file, perform verification using checks below.

## SOT Hierarchy for UI Tasks

1. **Figma** — PRIMARY SOT for ALL VISUAL:
   - Colors, spacing, typography
   - States visual appearance (hover, focus, active, disabled)
   - Responsive layouts and breakpoints
   - Animations and transitions
   - **NO TEXT FALLBACK** — if Figma unavailable, mark `[VISUAL_TODO]`, do NOT guess

2. **ui/\*.md** — PRIMARY SOT for STRUCTURE:
   - Props interface (types, required, defaults)
   - States (triggers, logic — NOT visual details)
   - Behavior (user actions, validation, error handling)
   - Accessibility (ARIA, keyboard, focus management)

3. **spec.md** — SECONDARY SOT for:
   - Behavior not detailed in ui/\*.md
   - User Story acceptance criteria
   - Edge cases

4. **contracts/** — TERTIARY SOT for:
   - API response types that map to Props
   - Error codes for error handling

**CRITICAL**: Verify that visual implementation matches Figma sources referenced in ui/\*.md. Text descriptions describe STRUCTURE/BEHAVIOR, Figma defines VISUAL.

## UI Verification Checks

For each completed UI component task, perform these checks:

**L2 Standard (UI)**:

- [ ] Component file exists at specified path
- [ ] Component exports match ui/\*.md component name
- [ ] Props interface matches ui/\*.md Props section (types, required flags)
- [ ] All states from ui/\*.md States table are implemented

**L4 Deep (UI)**:

- [ ] All L2 checks, plus:
- [ ] Event handlers match ui/\*.md Behavior table
- [ ] Validation rules match ui/\*.md Validation Rules
- [ ] Error handling matches ui/\*.md Error Handling section
- [ ] ARIA attributes from ui/\*.md Accessibility present
- [ ] Keyboard handlers implemented per ui/\*.md
- [ ] Focus management implemented per ui/\*.md

## Visual Verification (Required for UI components)

**Pre-verification**:

- [ ] All Figma sources in ui/\*.md Figma References are accessible
- [ ] No `[MCP_UNAVAILABLE]` markers without user acknowledgment

**Visual Marker Check**:

- [ ] No `[VISUAL_TODO]` markers remain (or explicitly acknowledged)
- [ ] No `[FIGMA_REVIEW_NEEDED]` markers remain
- [ ] Visual Status column in States table is complete (all `✓ Verified`)

**If visual markers found**:

- Create `ui_visual_todo` issue for each unresolved `[VISUAL_TODO]` marker
- Create `ui_figma_review_needed` issue for each `[FIGMA_REVIEW_NEEDED]` marker
- Create `ui_mcp_unavailable` issue for each `[MCP_UNAVAILABLE]` marker
- Severity: `medium` (blocks production deployment)
- Status: `requires_figma_access`

**Visual Mismatch Detection**:

- If implementation has visible styles but ui/\*.md has `[VISUAL_TODO]`:
  - Warn: "Styles implemented without Figma verification"
  - Create `ui_visual_mismatch` issue
  - Severity: `high` (unverified visual code)

**Figma Drift Detection** (optional, when discrepancy suspected):

If code and ui/\*.md match but visual looks wrong:

1. **Fetch fresh Figma data**:

   ```python
   design_context = mcp_figma_get_design_context(
       fileKey=figma_refs.file_key,
       nodeId=figma_refs.node_id
   )
   ```

2. **Compare**:
   - Code styles vs fresh Figma
   - ui/\*.md Visual Status vs fresh Figma

3. **Create issue if Figma changed**:
   ```typescript
   {
     type: "ui_figma_drift",
     description: "Figma design changed since implement-ui ran",
     fix_context: {
       figma_value: "16px",
       code_value: "12px",
       ui_spec_value: "12px",
       suggested_fix: "Re-run /speckit.implement-ui to get latest styles"
     }
   }
   ```

**Note**: Figma fetch is optional — only when visual discrepancy suspected.
Primary verification: code vs ui/\*.md (cheap, no API calls).

## Negative Specs Verification

**CRITICAL**: Check that elements listed in **Negative Specs** section of ui/\*.md are NOT present in implementation.

**Detection**:

1. Read `## Negative Specs` section from ui/\*.md
2. Parse table: each row with `❌ NO` status is a forbidden element
3. Search implementation file for forbidden elements

**Verification Checklist**:

- [ ] Parse Negative Specs table from ui/\*.md
- [ ] For each forbidden element, check implementation file
- [ ] Icons listed as "NO" → no icon imports/usage for that component
- [ ] Descriptions listed as "NO" → no description text/props
- [ ] Background elements listed as "NO" → no corresponding div/styles

**Element Detection Patterns**:

| Forbidden Element | Detection Pattern                                          |
| ----------------- | ---------------------------------------------------------- |
| Menu icons        | `<*Icon`, `import.*Icon`, `icon=`, `leftIcon`, `rightIcon` |
| Descriptions      | `description`, `subtitle`, `helperText`, `<p>` inside item |
| Background squares| `bg-*` on icon wrapper, `rounded-*` wrapper around icon    |

**Issue Creation Example**:

```typescript
{
  id: "V050",
  task_id: "T094",
  file: "/frontend/src/components/AddContentPopup.tsx",
  verification_level: "L2",
  confidence: 95,
  confidence_required: 80,
  severity: "medium",
  type: "ui_negative_spec_violation",
  description: "Component has icons but Negative Specs forbids: 'Menu item icons: ❌ NO'",
  source_of_truth: {
    type: "ui_spec",
    reference: "ui/AddContentPopup.md §Negative Specs",
    content: "| Menu item icons | ❌ NO | Node ABC123 does not contain icon children |",
    confidence: 100
  },
  fix_context: {
    can_fix_automatically: true,
    suggested_approach: "Remove icon imports and usage from menu items",
    affected_files: ["AddContentPopup.tsx"],
    requires_spec_update: false
  },
  status: "detected"
}
```

## Design System Manifest Verification

**Check if `design-system.json` exists** in project root:

1. **Token Usage Check**:
   - Search for hardcoded hex colors: `bg-[#`, `text-[#`, `border-[#`
   - For each found, check if hex exists in `design-system.json → tokens`
   - If token exists but hardcoded used → create `ds_token_violation` issue

2. **Component Import Check**:
   - For each component in `design-system.json → components`
   - Check if used in implementation
   - Verify import source matches `design-system.json → components → [name] → import`
   - Wrong import source → create `ds_import_violation` issue

**DS Issue Types**:

| Type                  | Description                          | Example                                     |
| --------------------- | ------------------------------------ | ------------------------------------------- |
| `ds_token_violation`  | Hardcoded color instead of token     | `bg-[#155DFC]` instead of `bg-primary`      |
| `ds_import_violation` | Wrong import source for DS component | Import Button from local instead of @lib/ui |

## Constitution Checks for UI

If `.specify/memory/constitution.md` defines UI principles, verify compliance:

1. **Design System**: If constitution requires specific design system:
   - Check component uses DS components (not custom atoms)
   - Check imports reference DS library

2. **Accessibility Level**: If constitution specifies WCAG level:
   - L4 verify all required ARIA attributes
   - Check color contrast (if design tokens available)

3. **Forbidden Patterns**: If constitution forbids patterns:
   - Check component doesn't use forbidden UI patterns
   - Create `ui_constitution_violation` issue if found

## UI Issue Types

| Type                         | Description                        | Example                                 |
| ---------------------------- | ---------------------------------- | --------------------------------------- |
| `ui_props_mismatch`          | Props interface doesn't match spec | Missing required prop `onSubmit`        |
| `ui_state_missing`           | State from spec not implemented    | Missing 'loading' state                 |
| `ui_behavior_missing`        | Event handler not implemented      | No `onCancel` handler                   |
| `ui_validation_missing`      | Validation rule not implemented    | Email validation missing                |
| `ui_a11y_missing`            | Accessibility feature missing      | No `aria-invalid` on error              |
| `ui_keyboard_missing`        | Keyboard handler missing           | Escape key doesn't close                |
| `ui_focus_missing`           | Focus management issue             | No auto-focus on mount                  |
| `ui_constitution_violation`  | Violates project UI principles     | Uses modal for form (forbidden)         |
| `ui_visual_todo`             | Unresolved [VISUAL_TODO] marker    | Component has 3 [VISUAL_TODO] markers   |
| `ui_figma_review_needed`     | Requires manual Figma review       | MCP returned low quality data           |
| `ui_mcp_unavailable`         | Figma MCP unavailable              | Component built from context only       |
| `ui_visual_mismatch`         | Visual doesn't match Figma         | Button color differs from Figma         |
| `ui_figma_drift`             | Figma design changed after styling | Re-run implement-ui for new styles      |
| `ui_negative_spec_violation` | Element from Negative Specs added  | Icon added but listed in Negative Specs |

## UI Issue Schema Example

```typescript
{
  id: "V042",
  task_id: "T094",
  file: "/frontend/src/components/LoginForm.tsx",
  verification_level: "L4",
  confidence: 92,
  confidence_required: 95,
  severity: "high",
  type: "ui_state_missing",
  description: "Missing 'error' state implementation",
  source_of_truth: {
    type: "ui_spec",
    reference: "ui/LoginForm.md §States",
    content: "| Error | spec.md | API error | Show error message |",
    confidence: 95
  },
  fix_context: {
    can_fix_automatically: true,
    suggested_approach: "Add error state handling with setFormState('error')",
    affected_files: ["LoginForm.tsx", "LoginForm.test.tsx"],
    requires_spec_update: false
  },
  status: "detected",
  uncertainty: {
    flags: [],
    confidence_reason: "Clear UI spec requirement, code missing state"
  }
}
```

## Graph Issue Types (UI-specific)

| Type                    | Description                       | Action                      |
| ----------------------- | --------------------------------- | --------------------------- |
| `graph_missing_trigger` | Modal/Popup without state trigger | Add useState for open/close |

**Note**: `graph_unused_export` and `graph_imported_not_used` are checked by `speckit.verify` (universal).
| `graph_missing_trigger` | Modal/Popup without state trigger | Add useState for open/close |

## Output Report

Generate UI verification section:

```markdown
## UI Component Verification

| Component | Props | States | Visual | Negative | DS  | Status   |
| --------- | ----- | ------ | ------ | -------- | --- | -------- |
| LoginForm | ✅    | ⚠️     | ✅     | ✅       | ✅  | 1 issue  |
| AddPopup  | ✅    | ✅     | 🔲     | ❌       | ✅  | 2 issues |

### UI Issues

| ID   | Component | Type                       | Description           |
| ---- | --------- | -------------------------- | --------------------- |
| V042 | LoginForm | ui_state_missing           | Missing 'error' state |
| V050 | AddPopup  | ui_negative_spec_violation | Has icons in menu     |
```

## Critical Rules

1. **Stateless**: No MCP Memory state management — verify handles caching
2. **SOT Priority**: ui/\*.md > spec.md > contracts for UI checks
3. **Figma First**: Visual details from Figma only, not text descriptions
4. **Negative Specs**: Missing forbidden elements = high confidence pass
