---
description: Generate UI component specifications from spec.md, plan.md, and optional Figma URL
handoffs:
  - label: Validate UI Specs
    agent: bash
    prompt: .specify/scripts/bash/validate-ui-specs.sh --ui-dir "$FEATURE_DIR/ui" --strict
  - label: Generate Tasks
    agent: speckit.tasks
    prompt: Generate tasks including UI component tasks
    send: true
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

**Supported arguments:**

### Figma URLs with Context (Multi-line format)

```text
/speckit.ui
https://figma.com/file/ABC123 — full registration form
https://figma.com/file/DEF456?node-id=100-200 — admin variant
https://figma.com/file/GHI789 — error and loading states
```

Each line: `URL — description` where:

- `URL` — Figma file or frame URL (may include `?node-id=`)
- `—` — Em dash separator (or `: ` also accepted)
- `description` — Context explaining what this frame represents

**Context quality tips** (the better context, the better result):

- Reference User Stories: `US2: form for administrator`
- Reference States: `State:Loading — skeleton and spinner`
- Reference conditions: `role=admin — additional fields`

### Extended Format (Optional, Recommended)

For best results, provide structured expert description:

```text
/speckit.ui
https://figma.com/file/ABC123 — US1: login form
  fields: email (required), password (required), remember_me (checkbox)
  buttons: Submit (primary), "Forgot password?" (link)
  state: default
  tokens: --spacing-md, --color-primary

https://figma.com/file/DEF456?node-id=100-200 — US1: login form (errors)
  state: error
  errors: inline under each field
  visual: red borders, error icon
```

Extended format fields:

- `fields:` — form fields with types/requirements
- `buttons:` — buttons with variants (primary, secondary, link)
- `state:` — which state this frame represents (default, loading, error, etc.)
- `errors:` — error display strategy
- `tokens:` — design tokens if known
- `visual:` — key visual notes

**Note**: Extended format is optional. Simple `URL — description` works, but extended gives better results when Figma MCP is unavailable.

### Flags

- `--skip-clarify` — Skip UI clarification questions phase
- `--simple-only` — Generate only simple (atom) component specs
- `--force` — Regenerate existing ui/\*.md files

## Language

All **produced project documentation** (new files you create or updates you write into markdown docs) MUST be written in **English**.

Source operational artifacts MUST remain in English:

- Commands (`.claude/commands/**`)
- Memory (`.specify/memory/**`)
- Document templates (`.specify/templates/**`)

Use these English sources as inputs, and write the actual output documents in English as well.

Target specs MUST be written in English:

- Constitution (`.specify/memory/constitution.md`)
- Output specs (`specs/**`)

Do **NOT** translate product/service names, technology names, library/framework names, acronyms, or other proper technical terms—keep their original spelling (typically English).

## Outline

### Phase 0: Prerequisites & Constitution Check

1. **Load prerequisites**:
   Run `.specify/scripts/bash/check-prerequisites.sh --json --require-plan` from repo root.
   Parse FEATURE_DIR and AVAILABLE_DOCS. All paths must be absolute.

2. **Validate required artifacts exist**:
   - **REQUIRED**: spec.md (for User Stories, Acceptance Scenarios)
   - **REQUIRED**: plan.md (for tech stack, project structure)
   - **OPTIONAL**: data-model.md (for entity types → Props)
   - **OPTIONAL**: contracts/ (for API response types)

   If spec.md or plan.md missing → ERROR: "Run /speckit.specify and /speckit.plan first"

3. **Load constitution** (if exists):
   Read `.specify/memory/constitution.md`

   Extract UI-relevant principles:

   ```
   ui_principles = {
       "design_system": extract_section("Design System"),  // e.g., "Use shadcn/ui"
       "accessibility": extract_section("Accessibility"),  // e.g., "WCAG 2.1 AA"
       "forbidden_patterns": extract_section("Forbidden"), // e.g., "No modals for forms"
       "mobile_first": extract_section("Mobile")          // e.g., "Mobile-first required"
   }
   ```

4. **Gate**: If constitution has strict UI rules that conflict with detected components, warn before proceeding:

   ```
   ⚠️ Constitution Check:
   - Design system: shadcn/ui required
   - Accessibility: WCAG 2.1 AA
   - Forbidden: Modal dialogs for data entry

   Detected components may need adjustment. Continue? [Y/n]
   ```

5. **Check for Design System manifest** (if exists):
   Read `design-system.json` from project root.

   If found, extract:

   ```
   design_system_manifest = {
       "library": ds["name"],           // e.g., "@apeekspace/ui"
       "tokens": ds["tokens"],          // hex → token name mapping
       "components": ds["components"],  // DS component list
       "fallback": ds["fallback"],      // shadcn-pattern fallback components
       "rules": ds["rules"]             // text rules for LLM
   }
   ```

   **For each UI element in spec** (3-level lookup):

   **Level 1 — DS component exists**: If component name matches `ds.components[name]`:
   - Mark as "Uses: @library/Component"
   - Do NOT create full spec (only override spec if needed)

   **Level 2 — Fallback available**: If component's **base UI primitive** matches a key in `ds.fallback.available_components`:

   Base primitive extraction — check the component name AND its classified type:
   ```
   # Name-based: strip feature prefix, check suffix/contains
   "EmployeesTable"    → base primitive "Table"     (suffix match)
   "SectionTabs"       → base primitive "Tabs"      (suffix match)
   "RoleSelect"        → base primitive "Select"    (suffix match)
   "ConfirmDialog"     → base primitive "Dialog"    (suffix match)
   "UserAvatar"        → base primitive "Avatar"    (suffix match)

   # Type-based: use classified Component Type from step 6
   Component Type "List" + Figma shows table layout → "Table"
   Component Type "Atom" + keyword "select"         → "Select"
   Component Type "Atom" + keyword "badge"          → "Badge"
   Component Type "Modal" + keyword "dialog"        → "Dialog"
   ```

   If a fallback match is found:
   - Mark as "Fallback: shadcn-pattern → @library/[Primitive]"
   - The **primitive** (Table, Tabs, Select) goes into DS library as a reusable component
   - The **feature wrapper** (EmployeesTable) gets a full ui/*.md spec that imports the DS primitive
   - Add prerequisite task: "Add [Primitive] to @library using shadcn pattern"
   - If `install` field present → include install command in task

   **Level 3 — Truly custom**: Component not found in either:
   - Generate full ui/*.md spec as usual
   - Component goes into feature code

   Use token classes (bg-primary) instead of hex values (bg-[#155DFC])

### Phase 0.5: Parse Figma Sources

**Skip if**: No Figma URLs in input

**CONTEXT-FIRST PRINCIPLE**:

```python
# Source of Truth Priority:
# 1. Expert description (STRUCTURE + BEHAVIOR) — always available
# 2. spec.md (ACCEPTANCE CRITERIA) — always available
# 3. Figma MCP (VISUAL DETAILS) — may be unavailable or low quality

source_priority = {
    "structure": "expert_description",  # fields, buttons, states
    "behavior": "spec.md",              # acceptance criteria, validation
    "visual": "figma"                   # ALL visual details — NO TEXT FALLBACK
}
```

1. **Parse multi-line Figma input** (supports extended format):

   **URL parsing helpers for Official Figma MCP:**

   ```python
   import re

   def extract_file_key(url: str) -> str:
       """Extract fileKey from Figma URL.
       URL formats:
       - https://figma.com/design/:fileKey/:fileName
       - https://figma.com/file/:fileKey/:fileName
       - https://figma.com/design/:fileKey/branch/:branchKey/:fileName (use branchKey)
       """
       # Check for branch URL first
       branch_match = re.search(r'figma\.com/design/([^/]+)/branch/([^/]+)', url)
       if branch_match:
           return branch_match.group(2)  # Return branchKey

       # Standard URL
       match = re.search(r'figma\.com/(?:design|file)/([^/]+)', url)
       return match.group(1) if match else None

   def extract_node_id(url: str) -> str | None:
       """Extract nodeId from Figma URL.
       Returns format "123:456" for Official Figma MCP.
       URL contains: ?node-id=123-456 or ?node-id=123:456
       """
       match = re.search(r'node-id=([0-9]+[-:][0-9]+)', url)
       if match:
           # Normalize to colon format: "123-456" → "123:456"
           return match.group(1).replace('-', ':')
       return None
   ```

   **Parse input:**

   ```python
   figma_sources = []
   current_source = None

   for line in arguments.split('\n'):
       line_stripped = line.strip()
       if not line_stripped or line_stripped.startswith('--'):
           continue

       # Check if this is a URL line or an extended property line
       if 'figma.com' in line_stripped:
           # Save previous source
           if current_source:
               figma_sources.append(current_source)

           # Parse "URL — description"
           if ' — ' in line_stripped:
               url, description = line_stripped.split(' — ', 1)
           elif ': ' in line_stripped and 'figma.com' in line_stripped.split(': ')[0]:
               url, description = line_stripped.split(': ', 1)
           else:
               url, description = line_stripped, None

           current_source = {
               "url": url.strip(),
               "description": description.strip() if description else None,
               "file_key": extract_file_key(url),
               "node_id": extract_node_id(url),  # Returns "123:456" format
               "extended": {}  # Extended format properties
           }

       elif current_source and line.startswith('  '):
           # Extended format: indented properties
           # e.g., "  fields: email, password"
           prop_line = line_stripped
           if ':' in prop_line:
               key, value = prop_line.split(':', 1)
               current_source['extended'][key.strip()] = value.strip()

   # Don't forget last source
   if current_source:
       figma_sources.append(current_source)
   ```

2. **Enrich context from spec.md**:

   For each Figma source with description, find related spec.md elements:

   ```python
   for source in figma_sources:
       desc = source['description']
       if not desc:
           continue

       source['spec_refs'] = {
           # Match "US1", "US2" etc in description
           "user_stories": find_user_story_refs(desc, spec_md),

           # Match "State:XXX" pattern
           "states": find_state_refs(desc),

           # Match role/condition patterns
           "conditions": find_condition_refs(desc)  # "role=admin", "isLoading"
       }
   ```

3. **Build source context map**:

   Create mapping for use during component generation:

   ```python
   figma_context_map = {
       source['file_key']: {
           "url": source['url'],
           "node_id": source['node_id'],
           "description": source['description'],
           "user_stories": source.get('spec_refs', {}).get('user_stories', []),
           "states": source.get('spec_refs', {}).get('states', []),
           "conditions": source.get('spec_refs', {}).get('conditions', [])
       }
       for source in figma_sources
   }
   ```

4. **Output parsed sources for confirmation**:
   ```
   ┌─────────────────────────────────────────────────────────────────┐
   │  Figma Sources                                                   │
   ├─────────────────────────────────────────────────────────────────┤
   │  # │ File Key  │ Node    │ Description            │ Spec Refs  │
   │  1 │ ABC123    │ -       │ full form              │ US1        │
   │  2 │ DEF456    │ 100-200 │ admin variant          │ US2, admin │
   │  3 │ GHI789    │ -       │ error states           │ State:Error│
   └─────────────────────────────────────────────────────────────────┘
   ```

### Phase 1: Component Discovery

**CRITICAL: Extraction Mode (NOT Interpretation)**

When analyzing Figma via MCP:

1. **Extract ONLY what exists in Figma**
   - Count actual children in Figma node
   - If no icon child → component has NO icon
   - If no description text → component has NO description

2. **Use EXACT colors from Figma**
   - Do NOT apply semantic substitution
   - `bg-[#155dfc]` from Figma for "Delete" button → use `bg-[#155dfc]`, NOT `variant="destructive"`
   - Let constitution token mapping handle conversion to token classes

3. **Zero additions policy**
   - If element NOT in Figma → NOT in spec
   - No "improvements" or "UX best practices" additions
   - When in doubt, leave it out

4. **Allowed interpretation (exceptions)**
   - Hover/focus/active states → deduce from DS patterns
   - Responsive breakpoints → follow constitution rules
   - Accessibility (aria-\*) → add always (WCAG 2.1 AA)
   - Keyboard navigation → add from DS component behavior

**Principle**: Strict extraction for VISUAL APPEARANCE, interpretation allowed for BEHAVIOR.

5. **Read spec.md** User Stories and Acceptance Scenarios

6. **Extract UI keywords** and classify component type:

   | Keyword Pattern                    | Component Type | Template |
   | ---------------------------------- | -------------- | -------- |
   | "page", "screen", "view"           | Page           | Full     |
   | "form", "input form", "data entry" | Form           | Full     |
   | "modal", "dialog", "popup"         | Modal          | Full     |
   | "card", "tile", "item"             | Card           | Full     |
   | "list", "table", "grid"            | List           | Full     |
   | "nav", "menu", "sidebar"           | Navigation     | Full     |
   | "button", "icon", "badge"          | Atom           | Simple   |
   | "input", "select", "checkbox"      | Atom           | Simple   |

7. **Check existing components**:
   - Scan project for existing components (path from plan.md, e.g., `frontend/src/components/`)
   - Create exclusion list of design system atoms
   - Check if ui/\*.md already exist (skip unless --force)

8. **Output component list for confirmation**:

   ```
   ┌─────────────────────────────────────────────────────────────────────────────────┐
   │  Detected UI Components                                                         │
   ├─────────────────────────────────────────────────────────────────────────────────┤
   │  # │ Component       │ Type │ Base Primitive │ User Story │ Action              │
   │  1 │ LoginForm       │ Form │ -              │ US1        │ Create spec         │
   │  2 │ EmployeesTable  │ List │ Table          │ US2        │ Fallback → DS Table │
   │  3 │ RoleSelect      │ Atom │ Select         │ US2        │ Fallback → DS Select│
   │  4 │ Button          │ Atom │ Button         │ -          │ Skip (DS exists)    │
   │  5 │ ProfilePage     │ Page │ -              │ US3        │ Create spec         │
   └─────────────────────────────────────────────────────────────────────────────────┘

   Legend:
   - "Skip (DS exists)": Already in @library — no spec needed
   - "Fallback → DS [X]": Primitive [X] will be added to @library (shadcn pattern).
     Feature wrapper (EmployeesTable) gets full spec that imports DS [X].
   - "Create spec": Fully custom — generate full ui/*.md

   DS prerequisite tasks will be generated:
   - Add Table to @apeekspace/ui (no new deps)
   - Add Select to @apeekspace/ui (install: @radix-ui/react-select)

   Proceed? [Y/n]
   ```

### Phase 1.5: UI Clarification Questions

**Skip if**: `--skip-clarify` flag or all behaviors are clearly defined in spec.md

For components with unclear behavior, ask up to **3 targeted questions**:

```markdown
## UI Clarification Questions

Based on spec.md analysis, I have these questions:

### Q1: Form Validation Strategy [LoginForm]

How should validation errors be displayed?

- [ ] Inline under each field (recommended for forms)
- [ ] Toast notification at top
- [ ] Error summary above submit button

**Recommendation**: Inline (industry standard for forms)

### Q2: Loading State [LoginForm, UserCard]

Which loading strategy for async operations?

- [ ] Inline button loading (spinner in button)
- [ ] Full overlay with spinner
- [ ] Skeleton placeholders

**Recommendation**: Inline button loading

### Q3: Error Recovery [All components]

How should users recover from errors?

- [ ] Retry button appears
- [ ] Auto-retry with backoff
- [ ] Manual page refresh required

**Recommendation**: Retry button
```

**Rules**:

- Max 3 questions total (focus on highest-impact decisions)
- Each question has 2-4 options with recommendations
- Group similar questions across components
- If no blocking uncertainties → skip to Phase 2

**After answers**: Encode responses directly into generated ui/\*.md files.

### Phase 2: Draft Generation (Pass 1/2)

For each component (not skipped):

1. **Determine template**:
   - Load `.specify/templates/ui-component-simple.md` for Atoms
   - Load `.specify/templates/ui-component-full.md` for Molecules/Organisms

2. **Apply constitution constraints** (from Phase 0):
   - Check component against forbidden patterns
   - Apply required accessibility level
   - Reference design system components in Dependencies

3. **Extract from spec.md**:
   - User Story reference
   - Acceptance Scenarios → Behavior table
   - Edge Cases → Error Handling section

4. **Extract from plan.md**:
   - Tech stack → TypeScript types (React/Vue/Svelte)
   - Project structure → **Path** field (e.g., `src/components/auth/LoginForm.tsx`)
   - Use plan.md file structure to determine exact path

5. **Extract from data-model.md** (if exists):
   - Entity fields → Props interface types
   - Relationships → nested component props

6. **Extract from contracts/** (if exists):
   - API response types → Props interface
   - Error codes → Error Handling section

7. **If Figma sources provided** (from Phase 0.5):

   **Official Figma MCP with Fallback**:

   ```python
   def fetch_figma_with_fallback(source, use_metadata_first=False):
       """Fetch Figma data with graceful fallback to expert context.

       Args:
           source: Figma source with file_key and node_id
           use_metadata_first: If True, fetch XML metadata first for large designs.
                              Use get_metadata for overview, then get_design_context
                              for specific nodes. Saves tokens on complex designs.
       """
       try:
           # For large designs: get structure overview first
           if use_metadata_first:
               metadata = mcp__figma__get_metadata(
                   fileKey=source['file_key'],
                   nodeId=source['node_id']
               )
               # Parse XML to identify key nodes, then fetch only those
               key_nodes = extract_key_nodes_from_metadata(metadata)
               # Proceed with selective fetching...

           # Use official Figma MCP get_design_context
           # Returns React-like code structure optimized for LLM interpretation
           design_context = mcp__figma__get_design_context(
               fileKey=source['file_key'],
               nodeId=source['node_id']  # format: "123:456" or "123-456"
           )

           # Optionally fetch design tokens (colors, spacing, typography)
           variable_defs = mcp__figma__get_variable_defs(
               fileKey=source['file_key'],
               nodeId=source['node_id']
           )

           figma_data = {
               "design_context": design_context,
               "variables": variable_defs
           }

           # Assess MCP response quality
           quality = assess_figma_quality(figma_data)

           if quality < 50:
               return {
                   "status": "low_quality",
                   "data": figma_data,
                   "markers": ["[FIGMA_REVIEW_NEEDED]"],
                   "fallback_to_context": True
               }

           return {"status": "ok", "data": figma_data, "markers": []}

       except Exception as e:
           # MCP unavailable or failed
           return {
               "status": "unavailable",
               "data": None,
               "markers": ["[MCP_UNAVAILABLE]"],
               "fallback_to_context": True,
               "error": str(e)
           }

   def assess_figma_quality(data):
       """Score MCP response quality (0-100)."""
       score = 0
       ctx = data.get("design_context", "")
       vars = data.get("variables", {})

       if len(ctx) > 100: score += 30           # Has substantial content
       if "className" in ctx: score += 20       # Has styling info
       if vars: score += 30                     # Has design tokens
       if "children" in ctx.lower(): score += 20  # Has component hierarchy
       return min(score, 100)
   ```

   For each Figma source in `figma_sources`:

   ```python
   for source in figma_sources:
       result = fetch_figma_with_fallback(source)
       context = figma_context_map[source['file_key']]

       if result['status'] == 'ok':
           # Use MCP data
           figma_data = result['data']
       elif result['fallback_to_context']:
           # Use expert context as primary, MCP as secondary
           figma_data = result.get('data')  # May be None or low quality
           # Mark all visual sections for review
           add_markers_to_visual_sections(result['markers'])

       # Map Figma frame to component states
       if context['states']:
           for state in context['states']:
               map_figma_to_state(figma_data, state, result['markers'])

       if context['conditions']:
           for condition in context['conditions']:
               map_figma_to_variant(figma_data, condition, result['markers'])

       if context['user_stories']:
           for us in context['user_stories']:
               associate_figma_with_story(figma_data, us)

       # If extended format provided, use it as PRIMARY for structure
       if source.get('extended'):
           extract_structure_from_extended(source['extended'])
   ```

   **Context-aware extraction**:
   - If description mentions "error" → extract error states
   - If description mentions "loading" → extract loading states
   - If description mentions "admin" → extract as role-conditional variant
   - If description references "US1", "US2" → group with that User Story's components
   - **If extended format provided** → use fields/buttons/state directly

   **Cross-source state building**:

   ```markdown
   ## States (built from multiple Figma sources)

   | State   | Figma Source   | Context            | Trigger         | Visual             | Visual Status |
   | ------- | -------------- | ------------------ | --------------- | ------------------ | ------------- |
   | Default | ABC123         | full form          | Initial         | Standard fields    | [VISUAL_TODO] |
   | Admin   | DEF456#100-200 | admin variant      | role=admin      | Extra fields       | [VISUAL_TODO] |
   | Error   | GHI789         | error states       | Validation fail | Red borders        | [VISUAL_TODO] |
   | Loading | GHI789         | loading states     | Submit          | Disabled + spinner | [VISUAL_TODO] |

   **Visual Status Legend**:

   - `[VISUAL_TODO]` — base styles extracted, details to be refined in `/speckit.implement-ui`
   - `[FIGMA_REVIEW_NEEDED]` — MCP returned low-quality data, manual review required
   - `[MCP_UNAVAILABLE]` — Figma unavailable, structure only from context
   - `✓ Verified` — fully verified against Figma
   ```

8. **Fill template** with extracted data

9. **Mark uncertain sections with [TODO]**:
   - Props without clear type → `[TODO] define type`
   - States without Figma reference → `[TODO] add Figma link`
   - Accessibility details → `[TODO] clarify ARIA attributes`

10. **Write DRAFT** to `FEATURE_DIR/ui/ComponentName.draft.md`

### Phase 2.5: Refinement (Pass 2/2)

Self-review and improve each draft:

1. **For each drafted component**:

   a. **Self-review checklist**:
   - [ ] Props have TypeScript types defined?
   - [ ] All states from spec.md covered?
   - [ ] Behavior matches acceptance scenarios?
   - [ ] Accessibility section has role, ARIA, keyboard?
   - [ ] Dependencies section filled?
   - [ ] [TODO] count reasonable (<5)?

   b. **Attempt to fill [TODO] markers**:
   - Re-read source documents for missing information
   - If information exists → fill the [TODO]
   - If information truly missing → keep [TODO]

   c. **Improve Props types**:
   - Replace `string` with union types where appropriate
   - Add proper callback signatures `(data: T) => Promise<void>`

   d. **Add missing handlers**:
   - Keyboard handlers from accessibility requirements
   - Error recovery handlers from error handling

2. **Finalize files**:
   - Rename `ComponentName.draft.md` → `ComponentName.md`
   - Delete draft files

### Phase 3: Asset Download (if Figma sources provided)

1. **Parse asset list** from generated ui/\*.md Assets tables

2. **Create output directories**:

   ```
   FEATURE_DIR/ui/assets/
   ├── icons/
   └── images/
   ```

3. **Download assets via Official Figma MCP** (for each source):

   ```python
   for source in figma_sources:
       assets = get_assets_from_source(source)
       for asset in assets:
           # Official Figma MCP uses get_screenshot for PNG export
           # Note: SVG export not directly supported, use PNG or manual export
           screenshot = mcp__figma__get_screenshot(
               fileKey=source['file_key'],
               nodeId=asset['node_id']  # format: "123:456"
           )
           # Screenshot is returned as base64 or URL, save to assets folder
   ```

   **Note**: Official Figma MCP only supports PNG screenshots via `get_screenshot`.
   For SVG assets, either:
   - Export manually from Figma
   - Use PNG format instead
   - Request user to export SVG assets

4. **Update asset paths** in ui/\*.md files

5. **Create multi-source manifest**:
   ```json
   {
     "created_at": "ISO_DATE",
     "downloaded_at": "ISO_DATE",
     "sources": [
       {
         "file_key": "ABC123",
         "url": "https://figma.com/file/ABC123",
         "node_id": null,
         "description": "full registration form",
         "spec_refs": {
           "user_stories": ["US1"],
           "states": [],
           "conditions": []
         }
       },
       {
         "file_key": "DEF456",
         "url": "https://figma.com/file/DEF456?node-id=100-200",
         "node_id": "100-200",
         "description": "admin variant",
         "spec_refs": {
           "user_stories": ["US2"],
           "states": [],
           "conditions": ["role=admin"]
         }
       },
       {
         "file_key": "GHI789",
         "url": "https://figma.com/file/GHI789",
         "node_id": null,
         "description": "error and loading states",
         "spec_refs": {
           "user_stories": [],
           "states": ["Error", "Loading"],
           "conditions": []
         }
       }
     ],
     "assets": [
       {
         "name": "icon-close",
         "source": "ABC123",
         "node": "123:456",
         "path": "assets/icons/close.svg",
         "description": "from full registration form"
       }
     ]
   }
   ```

### Phase 4: Validation & Report

1. **Run validation**:

   ```bash
   .specify/scripts/bash/validate-ui-specs.sh --ui-dir FEATURE_DIR/ui --json
   ```

2. **Create index file** `FEATURE_DIR/ui/_index.md`:

   ```markdown
   # UI Components Index

   **Feature**: [Feature Name]
   **Generated**: [DATE]
   **Total Components**: N

   ## Components

   | Component   | Type | Template | Status | [TODO] Count |
   | ----------- | ---- | -------- | ------ | ------------ |
   | LoginForm   | Form | Full     | ✓      | 2            |
   | UserCard    | Card | Full     | ✓      | 1            |
   | ProfilePage | Page | Full     | ⚠️     | 5            |

   ## Next Steps

   1. Review and fill remaining [TODO] markers
   2. Verify States against Figma designs
   3. Run `validate-ui-specs.sh --strict` before /tasks
   ```

3. **Output summary report**:

   ```
   ═══════════════════════════════════════════════════════════════
     UI Specs Generated
   ═══════════════════════════════════════════════════════════════

   Components: 3 created, 1 skipped (design system)
   [TODO] Markers: 8 total (need human review)
   Assets: 5 downloaded to ui/assets/

   ───────────────────────────────────────────────────────────────

   Required Human Review:
   - LoginForm.md: 2 [TODO] in Props Interface
   - ProfilePage.md: 5 [TODO] in Accessibility

   ───────────────────────────────────────────────────────────────

   Next Steps:
   1. Review ui/*.md files and fill [TODO] markers
   2. Run: validate-ui-specs.sh --ui-dir specs/NNN/ui --strict
   3. Then run: /speckit.tasks to generate implementation tasks

   💡 Visual details will be refined in `/speckit.implement-ui`.
      Run it with Figma access for accurate styling.

   ═══════════════════════════════════════════════════════════════
   ```

## Output Files

- `FEATURE_DIR/ui/*.md` — Component specifications
- `FEATURE_DIR/ui/_index.md` — Component index
- `FEATURE_DIR/ui/assets/` — Downloaded Figma assets (if URL provided)
- `FEATURE_DIR/ui/assets/manifest.json` — Asset manifest

## Critical Rules

1. **[TODO] > Guessing**: NEVER guess accessibility details, validation rules, or error messages. Mark as [TODO] instead.

2. **Constitution Compliance**: If constitution defines design system, always reference it in Dependencies.

3. **Human Review Required**: UI specs are DRAFTS until human fills [TODO] markers.

4. **Iterative Quality**: Two passes (draft → refined) to reduce [TODO] count.

5. **Clarification First**: Ask questions BEFORE generating specs, not after.

6. **Validation Gate**: `validate-ui-specs.sh --strict` must pass before /tasks.

7. **Visual = Figma ONLY**: NEVER describe visual details from text. Mark as `[VISUAL_TODO]` instead.

8. **MCP Fallback**: If Figma MCP fails, use expert context for structure but mark `[MCP_UNAVAILABLE]` for visual sections.

## Source of Truth Separation

**CRITICAL**: Text descriptions and Figma have DIFFERENT responsibilities.

| Aspect                         | Source             | Fallback           | Marker if Missing |
| ------------------------------ | ------------------ | ------------------ | ----------------- |
| Structure (fields, buttons)    | Expert description | spec.md            | `[TODO]`          |
| Behavior (validation, errors)  | spec.md            | Expert description | `[TODO]`          |
| **ALL VISUAL**                 | **Figma**          | **NONE**           | `[VISUAL_TODO]`   |

### What comes from TEXT (Expert description + spec.md)

- Component name and type
- Props interface (names, types, required)
- States (names, triggers, logic)
- Behavior (user actions, validation rules)
- Accessibility (roles, keyboard handlers)
- Error handling logic

### What comes ONLY from FIGMA

- ALL visual styling (colors, fonts, spacing)
- Component dimensions and layout
- State appearances (hover, focus, active, disabled)
- Animations and transitions
- Responsive breakpoints
- Asset references (icons, images)

**⚠️ FORBIDDEN**: Guessing visual details from text.
If Figma is unavailable → `[VISUAL_TODO]`, NOT "by eye".

### Marker Reference

| Marker                  | Meaning                                | When Used                     |
| ----------------------- | -------------------------------------- | ----------------------------- |
| `[TODO]`                | Structure/behavior info missing        | No clear type, missing rule   |
| `[VISUAL_TODO]`         | Visual details need Figma verification | All visual sections initially |
| `[FIGMA_REVIEW_NEEDED]` | MCP returned low quality data          | Quality score < 50%           |
| `[MCP_UNAVAILABLE]`     | Figma MCP failed                       | MCP error/timeout             |

## Context-to-Spec Mapping Strategy

**CRITICAL**: When processing Figma sources with context descriptions, ALWAYS cross-reference with loaded spec.md to maximize understanding.

### How Context Descriptions Help

| Description Pattern              | What LLM Should Do                                                                 |
| -------------------------------- | ---------------------------------------------------------------------------------- |
| `US1: login form`                | Find User Story 1 in spec.md, extract acceptance criteria → map to States/Behavior |
| `State:Error — validation errors`| This frame shows Error state → extract error visuals for States table              |
| `role=admin — additional fields` | Conditional variant → create variant state, extract additional fields              |
| `step 2 of 3`                    | Wizard step → part of multi-step flow, infer step transitions                      |
| `mobile version`                 | Responsive variant → document in Responsive section                                |

### Cross-Reference Process

```python
def enrich_figma_context(source, spec_md, plan_md):
    """For each Figma source, find related spec elements."""

    desc = source['description']
    enriched = {}

    # 1. Find User Story references
    us_matches = re.findall(r'US\d+|User Story \d+', desc, re.I)
    if us_matches:
        enriched['user_stories'] = []
        for us_ref in us_matches:
            story = find_story_in_spec(us_ref, spec_md)
            if story:
                enriched['user_stories'].append({
                    'ref': us_ref,
                    'title': story['title'],
                    'acceptance_criteria': story['acceptance_criteria']
                })

    # 2. Find State references
    state_matches = re.findall(r'State:(\w+)|state[s]?\s+(\w+)', desc, re.I)
    if state_matches:
        enriched['states'] = [s[0] or s[1] for s in state_matches]

    # 3. Find condition patterns
    cond_matches = re.findall(r'(\w+)=(\w+)|if\s+(\w+)', desc, re.I)
    if cond_matches:
        enriched['conditions'] = [
            f"{m[0]}={m[1]}" if m[0] else m[2]
            for m in cond_matches
        ]

    # 4. Infer from keywords
    if any(kw in desc.lower() for kw in ['error', 'fail']):
        enriched.setdefault('states', []).append('Error')

    if any(kw in desc.lower() for kw in ['loading', 'spinner']):
        enriched.setdefault('states', []).append('Loading')

    if any(kw in desc.lower() for kw in ['admin', 'moderator']):
        enriched.setdefault('conditions', []).append('role=admin')

    return enriched
```

### State Aggregation from Multiple Sources

When multiple Figma sources contribute to one component:

```markdown
## States

| State   | Figma          | Context                  | Trigger      | Behavior                     |
| ------- | -------------- | ------------------------ | ------------ | ---------------------------- |
| Default | ABC123         | full registration form   | Mount        | Show empty form              |
| Loading | GHI789         | loading states           | Submit click | Disable inputs, show spinner |
| Error   | GHI789         | error states             | API error    | Show inline errors from api  |
| Admin   | DEF456#100-200 | admin variant            | role=admin   | Show RoleSelector field      |

**Source Mapping**:

- Default state visual: ABC123 (full form)
- Error/Loading states: GHI789 (error and loading states)
- Admin variant: DEF456 node 100-200 (admin variant)
```

This traceability helps during `/speckit.verify` to validate implementation against correct Figma source.
