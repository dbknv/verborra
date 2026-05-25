# UI Component: [COMPONENT_NAME]

**Type**: Molecule | Organism
**Path**: [relative/path/to/Component.tsx]
**Feature**: [specs/NNN-feature/spec.md]
**User Story**: [US1, US2]
**Created**: [DATE]

---

## Figma References

<!-- Multiple Figma sources with context for traceability -->

| Source | URL                      | Node      | Context            | Maps To               |
| ------ | ------------------------ | --------- | ------------------ | --------------------- |
| Main   | [figma/file/ABC123](URL) | -         | Full form          | Default state         |
| Admin  | [figma/file/DEF456](URL) | `100-200` | Admin variant      | Admin variant         |
| States | [figma/file/GHI789](URL) | -         | Errors and loading | Error, Loading states |

**Source Summary**:

- Default visual: Main (ABC123)
- Error/Loading states: States (GHI789)
- Admin variant: Admin (DEF456#100-200)

---

## Visual Implementation

**SOURCE OF TRUTH**: Figma (see Figma References above)

### Source Responsibilities

| Source             | What it defines                                  |
| ------------------ | ------------------------------------------------ |
| Text context       | Structure (fields, buttons), behavior, states    |
| spec.md            | Acceptance criteria, edge cases                  |
| **Figma**          | **EVERYTHING VISUAL** — without exception        |

### What is taken ONLY from Figma

- Sizes, offsets, margins, paddings
- Colors (text, background, border)
- Fonts (family, size, weight, line-height)
- Shadows, border radii, borders
- Hover, focus, active, disabled states
- Animations and transitions
- Responsive breakpoints

**⚠️ FORBIDDEN**: guessing visual details.
If Figma is unavailable → `[VISUAL_TODO]`, not "by eye".

### Visual Status

| State   | Figma Source    | CSS Class             | Status        |
| ------- | --------------- | --------------------- | ------------- |
| Default | Main (ABC123)   | `.component`          | [VISUAL_TODO] |
| Loading | States (GHI789) | `.component--loading` | [VISUAL_TODO] |
| Error   | States (GHI789) | `.component--error`   | [VISUAL_TODO] |
| Admin   | Admin (DEF456)  | `.component--admin`   | [VISUAL_TODO] |

**Status Legend**:

- `[VISUAL_TODO]` — requires Figma verification
- `[FIGMA_REVIEW_NEEDED]` — MCP data was low quality
- `[MCP_UNAVAILABLE]` — built from context only
- `✓ Verified` — implementation matches Figma

---

## Negative Specs (What NOT to include)

> Elements that are **NOT in Figma** → **DO NOT add** to the implementation

| Element                                  | Status | Figma Proof                |
| ---------------------------------------- | ------ | -------------------------- |
| [TODO: fill in after analyzing Figma]    | ❌ NO  | [Node ID or description]   |

<!--
Examples:
| Icons in menu items | ❌ NO | Node ABC123 does not contain icon children |
| Descriptions under elements | ❌ NO | No text node with description role |
| Background squares for icons | ❌ NO | No rectangle child in icon group |
-->

**Principle**: If an element is not in Figma — it is not in the code.

---

## Props Interface

| Prop          | Type                         | Required | Default | Description            |
| ------------- | ---------------------------- | -------- | ------- | ---------------------- |
| `onSubmit`    | `(data: T) => Promise<void>` | Yes      | -       | [TODO] describe        |
| `initialData` | `T \| null`                  | No       | `null`  | Initial form data      |
| `isLoading`   | `boolean`                    | No       | `false` | External loading state |
| `onCancel`    | `() => void`                 | No       | -       | Cancel handler         |

---

## States

| State   | Figma Source           | Trigger                     | Visual                   | Logic                        | Visual Status |
| ------- | ---------------------- | --------------------------- | ------------------------ | ---------------------------- | ------------- |
| Default | Main (ABC123)          | Initial render              | Standard form            | -                            | [VISUAL_TODO] |
| Loading | States (GHI789)        | onSubmit called             | Disabled + spinner       | Disable inputs, show spinner | [VISUAL_TODO] |
| Error   | States (GHI789)        | API error / validation fail | Red borders, error text  | Show error message           | [VISUAL_TODO] |
| Success | -                      | API success                 | -                        | Close/redirect               | -             |
| Admin   | Admin (DEF456#100-200) | `role=admin`                | Extra RoleSelector field | Show additional fields       | [VISUAL_TODO] |

<!-- State source tracing helps /speckit.verify match implementation to correct Figma frame -->
<!-- Visual Status: [VISUAL_TODO] → verify against Figma, ✓ → verified -->

---

## Behavior

### User Actions

| Trigger      | Precondition  | Validation       | Action             | Result                  |
| ------------ | ------------- | ---------------- | ------------------ | ----------------------- |
| Click Submit | Form visible  | All fields valid | Call onSubmit      | Loading → Success/Error |
| Press Enter  | Focus in form | Same             | Same               | Same                    |
| Click Cancel | Form visible  | -                | Call onCancel      | Close without save      |
| Change field | Field visible | -                | Update local state | Re-validate             |

### Validation Rules

| Field    | Rule                          | Error Message           |
| -------- | ----------------------------- | ----------------------- |
| email    | RFC 5322 format               | "Invalid email format"  |
| password | min 8 chars, 1 upper, 1 digit | "Password is too weak"  |
| [field]  | [rule]                        | [message]               |

### Error Handling

| Error Type | Source       | Display            | Recovery             |
| ---------- | ------------ | ------------------ | -------------------- |
| Network    | API call     | Toast notification | Retry button         |
| Validation | Form submit  | Inline under field | Fix field value      |
| Server 500 | API response | Modal dialog       | Contact support link |
| Timeout    | API call     | Toast              | Auto-retry or manual |

---

## Accessibility

- **Role**: `form` | `dialog` | `[role]`
- **ARIA Attributes**:
  - `aria-invalid="true"` on error fields
  - `aria-describedby` → error message ID
  - `aria-busy="true"` during loading
  - `aria-live="polite"` for status updates
- **Keyboard Navigation**:
  - `Tab` → field navigation (natural order)
  - `Shift+Tab` → reverse navigation
  - `Enter` → submit (if valid)
  - `Escape` → cancel/close
- **Focus Management**:
  - Auto-focus first field on mount
  - Focus first error field on validation fail
  - Return focus to trigger on close

---

## Sub-components

<!-- For compound components (Modal with Header/Body/Footer, Tabs with Tab/Panel, etc.) -->

### [SubComponentName]

| Prop      | Type         | Required | Description   |
| --------- | ------------ | -------- | ------------- |
| `title`   | `string`     | Yes      | Header title  |
| `onClose` | `() => void` | No       | Close handler |

### [SubComponentName2]

| Prop       | Type        | Required | Description |
| ---------- | ----------- | -------- | ----------- |
| `children` | `ReactNode` | Yes      | Content     |

---

## Dependencies

**Uses**: (design system / shared components)

- `Button` from design system
- `Input` from design system
- `useForm` hook from `@/hooks`

**Used By**: (parent components / pages)

- `LoginPage`
- `AuthModal`

**External**:

- API endpoint: `POST /api/auth/login`
- Contract: `contracts/openapi.yaml#/paths/~1auth~1login`

---

## Assets

| Asset        | Figma Source    | Node     | Format | Path                        |
| ------------ | --------------- | -------- | ------ | --------------------------- |
| icon-close   | Main (ABC123)   | `123abc` | SVG    | `assets/icons/close.svg`    |
| icon-spinner | States (GHI789) | `456def` | SVG    | `assets/icons/spinner.svg`  |
| bg-pattern   | Main (ABC123)   | `789ghi` | PNG    | `assets/images/pattern.png` |

---

## Test Scenarios

### Unit Tests

- [ ] Renders with required props only
- [ ] Renders with all optional props
- [ ] Shows loading state when isLoading=true
- [ ] Displays validation errors on invalid input
- [ ] Calls onSubmit with correct data shape
- [ ] Calls onCancel when cancel clicked
- [ ] Handles disabled state correctly

### Integration Tests

- [ ] Full submit flow: fill → submit → loading → success
- [ ] Error flow: fill → submit → error → display → retry
- [ ] Validation flow: invalid input → error display → fix → clear error

### Accessibility Tests

- [ ] Passes axe-core audit
- [ ] Keyboard navigation works correctly
- [ ] Screen reader announces state changes
- [ ] Focus management works on open/close

---

## Notes

[Edge cases, known limitations, implementation hints, design decisions]

### Known Limitations

- [Limitation 1]
- [Limitation 2]

### Implementation Hints

- [Hint 1]
- [Hint 2]
