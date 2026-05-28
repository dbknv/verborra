---
description: Synthesize UI specs from pre-processed analysis documents using Voice Weight authority
handoffs:
  - label: Validate UI Specs
    agent: bash
    prompt: validate-ui-specs.sh --ui-dir $OUTPUT
    send: true
  - label: Generate Tasks
    agent: speckit.tasks
    prompt: Generate implementation tasks
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Language

All **produced project documentation** (new files you create or updates you write into markdown docs) MUST be written in **English**.

Source operational artifacts MUST remain in English:

- Commands (`.claude/commands/**`)
- Memory (`.specify/memory/**`)
- Document templates (`.specify/templates/**`)

Use these English sources as inputs, but when generating the actual output documents, write them in English.

Do **NOT** translate product/service names, technology names, library/framework names, acronyms, or other proper technical terms—keep their original spelling (typically English).

## Purpose

This command transforms pre-processed UI analysis documents (typically `ui-analysis.md`) into standardized UI component specifications (`ui/*.md`) using the Voice Weight algorithm from `/speckit.synthesize`.

**Key differentiator from `/speckit.ui`:**
- `/speckit.ui` starts from `spec.md` + Figma URL
- `/speckit.ui-synthesize` starts from existing UI analysis with expert notes + optional Figma

**Key differentiator from `/speckit.synthesize`:**
- `/speckit.synthesize` produces `spec.md`
- `/speckit.ui-synthesize` produces `ui/*.md` component specs

---

## Input Syntax

```
/speckit.ui-synthesize [options]
```

### Options

| Option | Description | Example |
|--------|-------------|---------|
| `--context path:weight` | Context file with Voice Weight (1-10) | `ui-analysis.md:9` |
| `--figma URL...` | Figma URLs for visual verification | `https://figma.com/file/ABC?node-id=123` |
| `--components Name1,Name2` | Filter to specific components | `MainNav,ShareDialog` |
| `--output path/` | Output directory for ui/*.md | `specs/008/ui/` |
| `--dry-run` | Analyze only, no file generation |  |
| `--verbose` | Show detailed analysis and decisions |  |
| `--skip-figma` | Context-only mode (all visual = [VISUAL_TODO]) |  |

### Examples

```bash
# Full synthesis with context and Figma
/speckit.ui-synthesize \
  --context specs/008/ui-analysis.md:9 \
  --figma "https://figma.com/file/H5I3AS240kw5jMQvquEtib?node-id=287-4682" \
  --output specs/008/ui/

# Specific components only
/speckit.ui-synthesize \
  --context specs/008/ui-analysis.md:9 \
  --components MainNav,SubSidebar,ShareDialog \
  --output specs/008/ui/

# Dry-run to preview
/speckit.ui-synthesize \
  --context specs/008/ui-analysis.md:9 \
  --dry-run --verbose

# Context-only mode (skip Figma)
/speckit.ui-synthesize \
  --context specs/008/ui-analysis.md:9 \
  --skip-figma \
  --output specs/008/ui/
```

---

## Execution Flow

### Phase 0: Parse Sources

**Run parse-ui-sources script** to parse all source arguments:

```bash
# Bash
SOURCES_JSON=$(.specify/scripts/bash/parse-ui-sources.sh \
  --context "$CONTEXT_ARG" \
  --figma "$FIGMA_URLS" \
  --components "$COMPONENTS" \
  --output "$OUTPUT_DIR" \
  --validate)

# PowerShell
$SourcesJson = .specify\scripts\powershell\parse-ui-sources.ps1 `
  -Context $ContextArg `
  -Figma $FigmaUrls `
  -Components $Components `
  -Output $OutputDir `
  -Validate
```

**Parse JSON output:**

```json
{
  "success": true,
  "context_sources": [
    { "path": "ui-analysis.md", "weight": 9, "exists": true, "size_bytes": 45000 }
  ],
  "figma_sources": [
    { "file_key": "H5I3AS240kw5jMQvquEtib", "node_id": "287-4682", "url": "..." }
  ],
  "component_filter": ["MainNav", "SubSidebar", "ShareDialog"],
  "output_dir": "specs/008/ui/",
  "stats": { "total_context_files": 1, "total_size_kb": 45 },
  "warnings": [],
  "errors": []
}
```

**GATE G0**: If `success: false` → ERROR with script's error messages

### Phase 1: Extract Components from Context

1. **Read context file(s)** into memory

2. **Parse component sections** using patterns:

   ```regex
   ### (?:\d+\.\s*)?(\w+)           # Component name: "### 7. ShareDialog"
   \*\*Node ID:\*\*\s*`?([0-9:,-]+)`?  # Node ID
   ⚠️\s*(.+?)(?:\n|$)               # Expert warnings
   ```

3. **Extract per component**:
   - `name` — component identifier
   - `description` — summary text
   - `node_ids` — Figma references from context
   - `structure` — tree format (├── / └── lines)
   - `states` — from States table if present
   - `design_tokens` — from code blocks (colors, spacing)
   - `expert_notes` — ⚠️ markers, "NOT" corrections, "ATTENTION" warnings

4. **Apply component filter** (if `--components` specified)

5. **Build Component Model**:

   ```json
   {
     "components": [
       {
         "name": "ShareDialog",
         "description": "Modal for sharing content",
         "node_ids": ["290:5997", "311:42309"],
         "structure": "Dialog frame 580×auto...",
         "states": ["default", "with_users", "link_access"],
         "expert_notes": [
           { "line": 453, "text": "Title uses 18px medium, NOT semibold" },
           { "line": 525, "text": "Dropdown width is 224px, NOT 239px" }
         ],
         "source_weight": 9
       }
     ]
   }
   ```

### Phase 2: Map Components to Figma

1. **For each component**, attempt Figma mapping:
   - **Direct Node ID match** — use `node_ids` from context
   - **Search by component name** — if no node_id in context
   - **Figma Reference table** — parse existing mapping if present

2. **If Figma MCP available** (use Official Figma MCP tools):
   ```python
   # Get design context (React-like code structure)
   design_context = mcp__figma__get_design_context(
       fileKey=file_key,
       nodeId=node_id  # format: "123:456"
   )

   # Get design tokens (colors, spacing, typography)
   variables = mcp__figma__get_variable_defs(
       fileKey=file_key,
       nodeId=node_id
   )

   # For large designs, get metadata overview first
   metadata = mcp__figma__get_metadata(
       fileKey=file_key,
       nodeId=node_id
   )
   ```
   - Extract visual properties from `design_context` and `variables`
   - Build `figma_data` with quality score

3. **If Figma MCP unavailable or `--skip-figma`**:
   - Set all visual properties to `[VISUAL_TODO]`
   - Add `[MCP_UNAVAILABLE]` marker if MCP failed

4. **Build Figma Map**:

   ```json
   {
     "component_figma_map": {
       "ShareDialog": {
         "primary_node": "290:5997",
         "additional_nodes": ["311:42309"],
         "figma_data": { ... },
         "quality_score": 0.85
       }
     }
   }
   ```

### Phase 3: Synthesize Component Specs

**For each component in scope:**

1. **Load template**: `.specify/templates/ui-component-full.md`

2. **Build Figma References table**:

   ```markdown
   ## Figma References

   | Source | URL | Node | Context | Maps To |
   |--------|-----|------|---------|---------|
   | Basic | [figma...](URL) | `290:5997` | Base state | Default |
   | Extended | [figma...](URL) | `311:42309` | Multiple users | Extended |
   ```

3. **Extract Props Interface** from context structure:
   - Parse tree structure for props and their types
   - Set `[TODO]` for unclear types

4. **Merge States** (context + Figma):
   - Use context for state names and triggers
   - Use Figma for visual appearance (or `[VISUAL_TODO]`)
   - Set all Visual Status to `[VISUAL_TODO]` initially

5. **Preserve Expert Notes** as HTML comments:

   **Input** (ui-analysis.md):
   ```markdown
   ├── Title "Share" (18px medium) ⚠️ NOT semibold!
   **Dimensions:** 224×112px (⚠️ NOT 239px!)
   ```

   **Output** (ui/ShareDialog.md):
   ```markdown
   <!-- EXPERT_NOTE: Title uses 18px medium, NOT semibold - source: ui-analysis.md:453 -->
   <!-- EXPERT_NOTE: Dropdown width is 224px, NOT 239px - source: ui-analysis.md:525 -->
   ```

6. **Apply Voice Weight for conflicts**:
   - Context (weight from arg) vs Figma MCP (weight 6)
   - If weight diff > 30%: auto-resolve to higher weight
   - If weight diff ≤ 30%: flag with comment

7. **Write component spec** to `output/ComponentName.md`

### Phase 4: Validation & Report

1. **Run validation script**:

   ```bash
   .specify/scripts/bash/validate-ui-specs.sh --ui-dir "$OUTPUT_DIR" --json
   ```

2. **Count markers**:
   - `[VISUAL_TODO]` — requires Figma verification
   - `[TODO]` — requires manual completion
   - `<!-- EXPERT_NOTE: ... -->` — preserved expert corrections

3. **Generate synthesis report**:

   ```markdown
   ## ✅ UI Specs Synthesized

   **Output**: `specs/008/ui/`
   **Components**: 12

   ### Synthesis Summary

   | Metric | Count |
   |--------|-------|
   | Components generated | 12 |
   | Expert notes preserved | 47 |
   | [VISUAL_TODO] markers | 36 |
   | [TODO] markers | 8 |

   ### Source Contributions

   | Source | Weight | Contributed |
   |--------|--------|-------------|
   | ui-analysis.md | 9 | Structure, states, behavior |
   | Figma (MCP) | 6 | Node IDs, basic hierarchy |

   ### Next Steps

   - Review `<!-- EXPERT_NOTE -->` comments
   - Run `/speckit.tasks` to generate implementation tasks
   - Or use `/speckit.ui --figma URL` for visual verification
   ```

---

## Voice Weight Algorithm

### For UI Synthesis

```
EffectiveWeight = ExplicitWeight × Significance × Freshness

Source Responsibilities:
- Context (ui-analysis.md) = STRUCTURE authority
  - Component hierarchy
  - Props and types
  - States and behavior
  - Accessibility requirements

- Figma = VISUAL authority (when available)
  - Colors, spacing, typography
  - Visual states appearance
  - Animations and transitions

- Expert Notes = HIGHEST priority (always preserved)
  - Corrections to common mistakes
  - Specific measurements
  - "NOT" overrides
```

### Conflict Resolution Rules

| Weight Differential | Action |
|---------------------|--------|
| > 30% | Auto-resolve to higher weight |
| ≤ 30% | Flag with `<!-- EXPERT_NOTE -->` comment |
| Expert correction (⚠️) | Always preserve as comment |
| ExplicitWeight = 10 | Absolute authority |

### Expert Notes Detection

**Patterns to detect:**
- `⚠️` followed by text
- `NOT ` corrections
- `ATTENTION` warnings
- Parenthetical corrections: `(not X, but Y)`

**Preservation format:**
```html
<!-- EXPERT_NOTE: {normalized_text} - source: {file}:{line} -->
```

---

## Dry-Run Mode (`--dry-run`)

When `--dry-run` flag is provided:

| Phase | Normal Mode | Dry-Run Mode |
|-------|-------------|--------------|
| Phase 0 | Parse sources | Parse sources |
| Phase 1 | Extract components | Extract components |
| Phase 2 | Map to Figma | Map to Figma (read-only) |
| Phase 3 | Write ui/*.md | **SKIP** (show preview) |
| Phase 4 | Validate | Validate preview |

**Dry-run output includes:**
- List of components to be generated
- Expert notes found (with line numbers)
- Figma mapping status
- Estimated file structure

---

## Error Handling

| Error | Response |
|-------|----------|
| No context file | ERROR "Context file required. Use --context path:weight" |
| Context file not found | ERROR "Context file not found: {path}" |
| Empty context file | ERROR "Context file is empty or unreadable" |
| No components found | ERROR "No UI components found in context file" |
| Output dir not writable | ERROR "Cannot write to output directory: {path}" |
| Invalid weight | WARN "Weight {W} out of range, clamping to 1-10" |
| Figma MCP unavailable | WARN "Figma MCP unavailable. Using context only. Visual = [VISUAL_TODO]" |
| Component not in filter | SKIP (silent) |

---

## Template Integration

### Template: ui-component-full.md

Used for all components. Key sections filled:

| Section | Source | Fallback |
|---------|--------|----------|
| Figma References | Context node_ids + Figma MCP | Empty table with [TODO] |
| Visual Implementation | Expert notes as comments | `[VISUAL_TODO]` markers |
| Props Interface | Context structure parsing | `[TODO] describe` |
| States | Context + Figma | Visual Status = `[VISUAL_TODO]` |
| Behavior | Context | Empty with `[TODO]` |
| Accessibility | Context | Basic template |

### Markers Used

| Marker | Meaning | When Added |
|--------|---------|------------|
| `[VISUAL_TODO]` | Requires Figma verification | All visual properties |
| `[TODO]` | Requires manual completion | Incomplete sections |
| `[MCP_UNAVAILABLE]` | Figma MCP was not accessible | Figma source unavailable |
| `<!-- EXPERT_NOTE: ... -->` | Preserved expert correction | From ⚠️ markers |

---

## Compatibility

### Upstream (Inputs)
- Uses existing `parse-sources.sh` weight syntax concepts
- Compatible with `common.sh` utilities
- Reads standard markdown format

### Downstream (Outputs)
- Output compatible with `validate-ui-specs.sh`
- Output compatible with `/speckit.tasks`
- Output compatible with `/speckit.implement`
- Output compatible with `/speckit.verify`

---

## Known Limitations

### Context Parsing
- Relies on consistent markdown structure in ui-analysis.md
- Tree notation (├── / └──) must use standard characters
- Component sections must start with `### ` heading

### Figma Integration
- MCP availability not guaranteed
- Quality score may vary by node complexity
- Complex variants may not map correctly

### Token Budget
- Large ui-analysis.md files (>50KB) may require chunking
- Recommend max 15-20 components per run
