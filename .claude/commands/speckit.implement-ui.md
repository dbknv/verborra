---
description: Style UI components per Figma design and ui/*.md specs
handoffs:
  - label: Verify UI
    agent: speckit.verify-ui
    prompt: Verify UI styling against specs
    send: true
---

## User Input

```text
$ARGUMENTS
```

**Supported arguments:**

- `--component ComponentName` — Style specific component only
- `--skip-figma` — Skip Figma fetch, use [VISUAL_TODO] markers

## Language

All **produced project documentation** MUST be written in **Russian**.
Source operational artifacts (commands, templates) MUST remain in English.

## Prerequisites

This command requires:

- `ui/*.md` exists (created by `/speckit.ui`)
- `[UI]` tasks in tasks.md (created by `/speckit.tasks`)
- Components created by `/speckit.implement` (functional, with `[STYLE_TODO]` markers)

## Outline

1. **Load Prerequisites**
   Run `.specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks` from repo root.
   Parse FEATURE_DIR and SRC_DIR. All paths must be absolute.

2. **Find UI Tasks**
   Run `.specify/scripts/bash/parse-tasks.sh --feature-dir "$FEATURE_DIR" --filter "[UI]" --status pending --json`

   If no `[UI]` tasks found:
   - Try fallback: `grep -l "\[STYLE_TODO\]" "$SRC_DIR"/**/*.tsx`
   - If still nothing → exit: "No UI tasks or [STYLE_TODO] markers found."

3. **Resolve Component File Paths**
   For each UI task (e.g., "T011 [UI] Style LoginForm"):

   **Primary — from ui/\*.md Path field:**

   ```markdown
   # ui/LoginForm.md

   **Path**: frontend/src/components/auth/LoginForm.tsx
   ```

   **Fallback — convention + find:**

   ```bash
   find "$SRC_DIR" -name "LoginForm.tsx" -type f
   ```

   **Fallback 2 — ask user:**

   ```
   Multiple matches for LoginForm:
   1. frontend/src/components/auth/LoginForm.tsx
   2. frontend/src/components/legacy/LoginForm.tsx
   Select [1-2]:
   ```

4. **Find [STYLE_TODO] Markers** (hints for precision)

   ```bash
   grep -n "\[STYLE_TODO\]" "$COMPONENT_FILE"
   ```

   Output example:

   ```
   15:  {/* [STYLE_TODO] Container: padding, background */}
   22:  // [STYLE_TODO] Input: border, focus state
   ```

   **If no markers**: Style entire component per ui/\*.md spec.

5. **Load Visual Specs from ui/\*.md**
   For each component, extract from its ui/\*.md:
   - **Figma References** table → URLs for each state
   - **Visual Status** table → what needs styling
   - **Dependencies** → design system imports

5.5. **Fetch Figma Visual Details** (REQUIRED unless `--skip-figma`)

For each component being styled:

a. **Get Figma URL from ui/\*.md Figma References table**

b. **Fetch focused visual data**:
```python # Focus extraction prompt — ONLY visual details:
VISUAL_FOCUS = """
Extract ONLY visual styling details: 1. Exact spacing values (padding, margin, gap) 2. Colors (background, text, border) — hex or token 3. Typography (font-size, font-weight, line-height) 4. Border radius values 5. Shadow values 6. Hover state changes 7. Focus state changes (ring, outline) 8. Active/pressed state changes 9. Disabled state changes 10. Transition properties (duration, easing)

      DO NOT extract structure — already known from ui/*.md.
      """

      design_context = mcp_figma_get_design_context(
          fileKey=figma_url.file_key,
          nodeId=figma_url.node_id
      )
      variable_defs = mcp_figma_get_variable_defs(
          fileKey=figma_url.file_key,
          nodeId=figma_url.node_id
      )
      ```

c. **Merge with ui/\*.md base styles**:
`python
      for element in component.elements:
          base_style = ui_spec.get_style(element)  # From ui/*.md
          figma_style = visual_details.get(element)  # From fresh Figma
          # Figma overrides ui/*.md for visual details
          final_style = {**base_style, **figma_style}
      `

d. **Handle Figma unavailable**: - Use ui/_.md styles as-is - Add `[VISUAL_TODO]` comment in code - Warn: "Figma unavailable. Styles from ui/_.md only — verify manually."

6. **Fetch Figma Data** (unless `--skip-figma`)
   For each Figma URL in ui/\*.md:
   - Call Figma MCP to get node styles
   - Extract: colors, spacing, typography, shadows
   - Map to design-system.json tokens if available

   **If Figma unavailable**:
   - Add `[VISUAL_TODO]` markers
   - Continue with placeholder styles
   - Warn user: "Figma unavailable. Styles need manual verification."

7. **Apply Styles**
   For each `[STYLE_TODO]` marker or unstyled element:

   a. **Primary source**: Fresh Figma data (from step 5.5)
   b. **Fallback**: ui/\*.md Visual Status table
   c. **Map to design tokens** if `design-system.json` exists:
   - Figma `#155DFC` → check tokens → `bg-primary-600`
   - No token → use exact: `bg-[#155DFC]`
     d. **Apply Tailwind/CSS classes**
     e. **Remove [STYLE_TODO] comment**

   **State styling** (from Figma variants):

   ```tsx
   // Default state from Figma
   className = "px-4 py-2 bg-primary-600 text-white rounded-md";

   // Hover from Figma variant
   className = "... hover:bg-primary-700";

   // Focus from Figma variant
   className = "... focus:ring-2 focus:ring-primary-500 focus:ring-offset-2";

   // Transition from Figma
   className = "... transition-colors duration-150";
   ```

   **Example transformation:**

   ```tsx
   // BEFORE
   <button type="submit">
     {/* [STYLE_TODO] Button: colors, hover */}
     Login
   </button>

   // AFTER
   <button
     type="submit"
     className="px-4 py-2 bg-primary-600 text-white rounded hover:bg-primary-700 transition-colors"
   >
     Login
   </button>
   ```

8. **Update Visual Status in ui/\*.md**
   After styling each component, update its ui/\*.md:

   a. **Replace [VISUAL_TODO] with actual values**:

   ```markdown
   BEFORE:
   | Default | ABC123 | `.btn` | [VISUAL_TODO] |

   AFTER:
   | Default | ABC123 | `px-4 py-2 bg-primary-600 text-white rounded-md` | ✓ Verified |
   ```

   b. **Add discovered states** (if found in Figma but not in spec):

   ```markdown
   | Hover | ABC123 | `hover:bg-primary-700` | ✓ Verified |
   | Focus | ABC123 | `focus:ring-2 focus:ring-primary-500` | ✓ Verified |
   ```

   c. **Mark unverified** if Figma unavailable:

   ```markdown
   | Default | ABC123 | `px-4 py-2 bg-primary-600` | [VISUAL_TODO] Figma unavailable |
   ```

   d. **Mark mismatch** if discrepancy found:
   - Change status to `[FIGMA_MISMATCH: description]`

9. **Mark Tasks Complete**
   Update tasks.md: `- [ ] T011 [UI]` → `- [X] T011 [UI]`

10. **Report Summary**

    ```
    ✅ Styled 3 components:
    - LoginForm.tsx (5 [STYLE_TODO] resolved)
    - RegisterForm.tsx (3 [STYLE_TODO] resolved)
    - Button.tsx (2 [STYLE_TODO] resolved)

    ⚠️ 1 component needs manual review:
    - Modal.tsx ([VISUAL_TODO] markers remain - Figma unavailable)

    💡 Next: Run /speckit.verify-ui to validate styling
    ```

## Critical Rules

1. **DO NOT modify**:
   - Function signatures
   - Props interfaces
   - State management logic
   - Event handler logic
   - Accessibility attributes (aria-\*, role)
   - Test files

2. **ONLY modify**:
   - `className` attributes
   - `style` objects
   - CSS/Tailwind classes
   - Wrapper divs for layout (if needed for styling)

3. **If logic change needed**:
   - Add comment: `// [LOGIC_ISSUE] description`
   - Do NOT fix it
   - Report in output summary

4. **Figma is SOT for visuals**:
   - Never guess colors, spacing, typography
   - No "looks about right" decisions
   - If uncertain → `[VISUAL_TODO]`

5. **Design System priority**:
   - Use tokens from `design-system.json` when available
   - Use exact Figma values when no token matches
   - Never substitute based on semantic meaning

## Issue Types

| Type                  | Description              | Action             |
| --------------------- | ------------------------ | ------------------ |
| `ui_style_incomplete` | [STYLE_TODO] remains     | Style from Figma   |
| `ui_visual_todo`      | [VISUAL_TODO] remains    | Get Figma access   |
| `ui_figma_mismatch`   | Style differs from Figma | Review discrepancy |
| `ui_logic_issue`      | Logic change needed      | Report, don't fix  |
