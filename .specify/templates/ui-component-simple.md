# UI Component: [COMPONENT_NAME]

**Type**: Atom
**Path**: [relative/path/to/Component.tsx]
**Feature**: [specs/NNN-feature/spec.md]
**User Story**: [US reference if applicable]
**Figma**: [URL or "N/A"]
**Created**: [DATE]

---

## Props

| Prop       | Type                       | Required | Default     | Description    |
| ---------- | -------------------------- | -------- | ----------- | -------------- |
| `variant`  | `'primary' \| 'secondary'` | No       | `'primary'` | Visual variant |
| `disabled` | `boolean`                  | No       | `false`     | Disabled state |
| `onClick`  | `() => void`               | No       | -           | Click handler  |

---

## States

| State    | Trigger         | Figma Frame | CSS Class              |
| -------- | --------------- | ----------- | ---------------------- |
| Default  | -               | [link]      | `.component`           |
| Hover    | Mouse over      | [link]      | `.component:hover`     |
| Active   | Mouse down      | [link]      | `.component:active`    |
| Focus    | Keyboard focus  | [link]      | `.component:focus`     |
| Disabled | `disabled=true` | [link]      | `.component--disabled` |

---

## Negative Specs (What NOT to include)

> Elements that are **NOT in Figma** → **DO NOT add** to the implementation

| Element                                  | Status | Figma Proof                |
| ---------------------------------------- | ------ | -------------------------- |
| [TODO: fill in after analyzing Figma]    | ❌ NO  | [Node ID or description]   |

**Principle**: If an element is not in Figma — it is not in the code.

---

## Accessibility

- **Role**: `button` | `link` | `[role]`
- **ARIA**: `aria-label`, `aria-disabled`
- **Keyboard**:
  - `Enter` / `Space` → trigger action
  - `Tab` → focus navigation

---

## Dependencies

**Uses**: (design system components this component uses)

- None (leaf component)

**Used By**: (components that use this one)

- [ParentComponent]

---

## Notes

[Any edge cases, known limitations, or implementation hints]
