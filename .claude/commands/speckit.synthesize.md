---
description: Synthesize a high-quality specification from multiple pre-generated, reviewed but inconsistent source documents using weighted voice authority and automatic significance scoring.
handoffs:
  - label: Clarify Spec Requirements
    agent: speckit.clarify
    prompt: Clarify specification requirements
    send: true
  - label: Build Technical Plan
    agent: speckit.plan
    prompt: Create a plan for the spec. I am building with...
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Language

All **produced project documentation** (new files you create or updates you write into markdown docs) MUST be written in **Russian**.

Source operational artifacts MUST remain in English:

- Commands (`.claude/commands/**`)
- Memory (`.specify/memory/**`)
- Document templates (`.specify/templates/**`)

Use these English sources as inputs, but when generating the actual output documents, write them in Russian.

Target specs MUST be translates to Russian:

- Constitution (`.specify/memory/constitution.md`)
- Output specs (`specs/**`)

Do **NOT** translate product/service names, technology names, library/framework names, acronyms, or other proper technical terms—keep their original spelling (typically English).

## Purpose

This command creates a consolidated, high-quality specification from multiple pre-existing source documents (drafts, notes, research, previous specs). Unlike `/speckit.specify` which starts from a brief description, `/speckit.synthesize` leverages developer-reviewed materials where more thought and attention has already been invested.

**Key differentiator:** Sources have explicit or computed **Voice Weight** that determines conflict resolution priority.

## Input Syntax

```
/speckit.synthesize [sources...] [options]
```

### Source Types

| Type                         | Syntax          | Example        | Description              |
| ---------------------------- | --------------- | -------------- | ------------------------ |
| **File with weight**         | `path:W`        | `draft.md:8`   | Single file, weight 1-10 |
| **File with weight & order** | `path:W:O`      | `req.md:9:1`   | Weight + load order      |
| **Folder (auto-scan)**       | `folder/:W`     | `notes/:3`     | All .md files in folder  |
| **Text search**              | `"description"` | `"API docs"`   | Semantic file search     |
| **Glob pattern**             | `pattern:W`     | `specs/*.md:6` | Pattern matching         |

**Parameters:**

- `W` = Voice Weight (1-10), default: 5
- `O` = Load Order (1-N), default: auto by significance

### Options

| Option            | Description                                                                   |
| ----------------- | ----------------------------------------------------------------------------- |
| `--auto`          | LLM determines significance and order automatically                           |
| `--strict`        | Any conflict creates [CONFLICT] marker (no auto-resolution)                   |
| `--verbose`       | Output source map and decision rationale                                      |
| `--dry-run`       | Analysis only, no spec generation                                             |
| `--max-sources N` | Limit number of source files (default: 10, hard max: 15)                      |
| `--single-pass`   | Force single-pass processing (faster, may reduce quality for complex sources) |

### Examples

```bash
# Minimal - single file
/speckit.synthesize draft-feature.md

# Multiple sources with weights
/speckit.synthesize requirements.md:9 notes.md:3 brainstorm.md:2

# Explicit load order (arch first, then requirements, then notes)
/speckit.synthesize arch.md:7:1 requirements.md:8:2 notes/:4:3

# Folder + semantic search
/speckit.synthesize drafts/:5 "architecture documentation"

# Full control with verbose output
/speckit.synthesize spec-draft.md:10:1 user-research.md:7:2 --verbose
```

### End-to-End Example

```
INPUT:
/speckit.synthesize requirements.md:9 arch-notes.md:6 brainstorm.md:2 --verbose

PHASE 0 (parse-sources.sh):
→ Parsed 3 files, total 28KB, no search queries

PHASE 1 (LLM analysis):
→ Source Analysis:
  | File              | Weight | Significance | Effective |
  | requirements.md   | 9      | 0.85         | 7.65      |
  | arch-notes.md     | 6      | 0.72         | 4.32      |
  | brainstorm.md     | 2      | 0.45         | 0.90      |

PHASE 2 (Conflict detection):
→ Found 2 conflicts:
  1. "Auth method" - requirements(OAuth2+API) vs arch(OAuth2 only)
     Resolved: OAuth2+API (weight diff 43%)
  2. "Rate limit" - requirements(1000/min) vs arch(500/min)
     Resolved: 1000/min (higher specificity)

PHASE 3 (synthesize-setup.sh):
→ Created branch: 007-user-auth
→ Created: specs/007-user-auth/spec.md

PHASE 4 (Spec generation):
→ Generated spec with 8 user stories, 12 requirements
→ Synthesis Metadata added

PHASE 5 (Validation):
→ Checklist created: specs/007-user-auth/checklists/requirements.md
→ 0 [CONFLICT] markers, 1 [NEEDS CLARIFICATION] marker

PHASE 6 (Report):
✅ Specification Synthesized
Branch: 007-user-auth
Spec: specs/007-user-auth/spec.md
Next: /speckit.clarify or /speckit.plan
```

---

## Execution Flow

### Dry-Run Mode (`--dry-run`)

When `--dry-run` flag is provided, the command performs analysis without creating any files or branches:

| Phase   | Normal Mode        | Dry-Run Mode                            |
| ------- | ------------------ | --------------------------------------- |
| Phase 0 | Parse sources      | Parse sources                           |
| Phase 1 | Load & score files | Load & score files                      |
| Phase 2 | Detect conflicts   | Detect conflicts                        |
| Phase 3 | Create branch/dirs | **SKIP** (report what would be created) |
| Phase 4 | Generate spec      | **SKIP** (show spec preview)            |
| Phase 5 | Validate           | Validate preview                        |
| Phase 6 | Report             | Report with "DRY-RUN" marker            |

**Dry-run output includes:**

- Source analysis table with weights and significance scores
- Detected conflicts and proposed resolutions
- Preview of spec structure (headings only)
- Estimated token usage for full synthesis

### Phase 0: Parse Input & Resolve Sources

**Run parse-sources script** to parse all source arguments:

```bash
# Bash
SOURCES_JSON=$(.specify/scripts/bash/parse-sources.sh \
  $ARGUMENTS \
  --max-sources 10 \
  --validate)

# PowerShell
$SourcesJson = .specify\scripts\powershell\parse-sources.ps1 `
  $Arguments `
  -MaxSources 10 `
  -Validate
```

**Script handles:**

- Parsing `path:W:O` syntax
- Folder expansion (`notes/:5` → list of .md files)
- Glob pattern matching (`*.md:6`)
- Deduplication (highest weight wins)
- File existence validation
- Size warnings (>20KB files)

**Parse JSON output:**

```json
{
  "success": true,
  "sources": [
    {
      "path": "req.md",
      "weight": 9,
      "order": 1,
      "exists": true,
      "size_bytes": 12340
    }
  ],
  "search_queries": ["API docs"],
  "stats": { "total_files": 5, "total_size_kb": 45 }
}
```

**Handle search queries** (if any in `search_queries`):

- Use Glob/Grep to find matching .md files
- Add found files to sources with weight 5

**Note**: For single quotes in args like "I'm Groot", use escape syntax: e.g., `'I'\''m Groot'` (or double-quote if possible: `"I'm Groot"`).

**GATE G0**: If `success: false` or `total_files: 0` → ERROR with script's error messages

### Phase 1: Load & Score Sources

1. **Read all source files** into memory with metadata:

   ```json
   {
     "path": "/absolute/path/to/file.md",
     "content": "...",
     "explicit_weight": 8,
     "explicit_order": null,
     "file_modified": "2024-01-15T10:30:00Z"
   }
   ```

2. **Calculate Significance Score** for each source (0.0-1.0):

   **Scoring Criteria:**

   | Criterion    | Weight | High Score Indicators                     |
   | ------------ | ------ | ----------------------------------------- |
   | Completeness | 0.25   | Covers multiple aspects, no major gaps    |
   | Specificity  | 0.25   | Concrete metrics, numbers, named entities |
   | Consistency  | 0.20   | No internal contradictions                |
   | Relevance    | 0.15   | Directly addresses feature scope          |
   | Structure    | 0.15   | Has headings, lists, scenarios            |

   **Auto-detection signals:**
   - Contains `Given/When/Then` or acceptance criteria → +0.2 Completeness
   - Contains numbers/percentages/time metrics → +0.2 Specificity
   - Has `## ` or `### ` headings → +0.1 Structure
   - Contains `TODO`, `???`, `TBD` → -0.15 Completeness
   - Contains "should be intuitive/robust/good" without metrics → -0.1 Specificity

3. **Calculate Freshness Multiplier** (0.8-1.0):

   ```
   days_old = (now - file_modified).days
   freshness = 1.0 - min(days_old / 365, 1.0) * 0.2
   ```

4. **Calculate Effective Weight**:

   ```
   EffectiveWeight = ExplicitWeight × SignificanceScore × FreshnessMultiplier
   ```

5. **Determine Load Order**:
   - If explicit order provided → use it
   - Otherwise → sort by EffectiveWeight descending
   - **Rationale**: Higher-weight sources load first, establishing baseline context

6. **Output Source Map** (always, detailed if `--verbose`):

   ```markdown
   ## Source Analysis

   | #   | File            | Explicit W | Significance | Freshness | Effective W | Order |
   | --- | --------------- | ---------- | ------------ | --------- | ----------- | ----- |
   | 1   | requirements.md | 9          | 0.85         | 0.95      | 7.27        | 1     |
   | 2   | arch-notes.md   | 7          | 0.72         | 0.88      | 4.44        | 2     |
   | 3   | brainstorm.md   | 3          | 0.45         | 1.00      | 1.35        | 3     |
   ```

### Phase 2: Content Analysis & Conflict Detection

1. **Extract structured information** from each source in load order:

   For each source, identify and tag:
   - **User Stories** (who, what, why patterns)
   - **Functional Requirements** (MUST/SHOULD/MAY statements)
   - **Success Criteria** (measurable outcomes)
   - **Entities** (nouns that represent data objects)
   - **Constraints** (limitations, boundaries)
   - **Edge Cases** (error scenarios, boundaries)
   - **Assumptions** (implicit decisions)

2. **Build Consolidated Model** with provenance:

   ```json
   {
     "user_stories": [
       {
         "content": "User can export data to CSV",
         "sources": [{ "file": "requirements.md", "weight": 7.27 }],
         "confidence": 0.9
       }
     ],
     "conflicts": [
       {
         "topic": "Authentication method",
         "positions": [
           { "content": "OAuth2 only", "source": "arch.md", "weight": 4.44 },
           {
             "content": "OAuth2 + API keys",
             "source": "requirements.md",
             "weight": 7.27
           }
         ]
       }
     ]
   }
   ```

3. **Detect Conflicts** - same topic, different values:
   - Compare entities with same name but different attributes
   - Compare requirements covering same functionality
   - Compare success criteria for same outcome

4. **Resolve Conflicts** using Voice Weight Algorithm + Multi-Lens Analysis:

   ```
   For each conflict:
     weight_diff = abs(position_A.weight - position_B.weight) / max(weights)

     If weight_diff > 0.30:
       # Clear winner - use higher weight source
       resolution = position_with_higher_weight
       log: "Resolved: {topic} → {resolution} (weight differential: {diff}%)"

     Else if --strict flag:
       # Create marker for manual resolution
       create_marker("[CONFLICT: {topic}] Source A says X, Source B says Y")

     Else:
       # INVOKE MULTI-LENS ANALYSIS for close calls
       analysis = multi_lens_analysis(conflict)

       If analysis.confidence >= 0.7:
         resolution = analysis.recommendation
         log: "Resolved via multi-lens: {topic} → {resolution} (confidence: {conf}%)"
       Else:
         # Low confidence - need user input
         create_marker("[CONFLICT: {topic}] Multi-lens inconclusive: {summary}")
   ```

5. **Log Conflict Resolution** (if `--verbose`):

   ```markdown
   ## Conflict Resolution

   | Topic       | Winner     | Weight | Loser       | Weight | Method      |
   | ----------- | ---------- | ------ | ----------- | ------ | ----------- |
   | Auth method | OAuth2+API | 7.27   | OAuth2 only | 4.44   | weight_diff |
   | Rate limit  | 1000/min   | 5.12   | 500/min     | 4.89   | specificity |
   ```

### Phase 3: Branch & Spec Setup

1. **Generate short name** from consolidated understanding:
   - Extract 2-4 keywords from highest-weight source's title/content
   - Format as `action-noun` pattern (e.g., `user-auth`, `payment-flow`)

2. **Run synthesize-setup script** to create branch and directories:

```bash
# Bash (normal mode)
SETUP_JSON=$(.specify/scripts/bash/synthesize-setup.sh \
  --feature-name "{short-name}" \
  --sources-json "$SOURCES_JSON")

# Bash (dry-run mode)
SETUP_JSON=$(.specify/scripts/bash/synthesize-setup.sh \
  --feature-name "{short-name}" \
  --sources-json "$SOURCES_JSON" \
  --dry-run)

# PowerShell (normal mode)
$SetupJson = .specify\scripts\powershell\synthesize-setup.ps1 `
  -FeatureName "{short-name}" `
  -SourcesJson $SourcesJson

# PowerShell (dry-run mode)
$SetupJson = .specify\scripts\powershell\synthesize-setup.ps1 `
  -FeatureName "{short-name}" `
  -SourcesJson $SourcesJson `
  -DryRun
```

**Script handles:**

- Checking for existing branches and specs directories
- Calculating next feature number (e.g., 007)
- Creating git branch `{NNN}-{short-name}`
- Creating directory structure:
  - `specs/{NNN}-{short-name}/`
  - `specs/{NNN}-{short-name}/checklists/`
  - `specs/{NNN}-{short-name}/contracts/`
  - `specs/{NNN}-{short-name}/verification/`
- Initializing empty `spec.md` with synthesis metadata header

3. **Parse JSON output**:

```json
{
  "success": true,
  "BRANCH_NAME": "007-user-auth",
  "FEATURE_DIR": "/path/to/specs/007-user-auth",
  "SPEC_FILE": "/path/to/specs/007-user-auth/spec.md",
  "CHECKLIST_DIR": "/path/to/specs/007-user-auth/checklists",
  "sources_validated": 5,
  "created": true,
  "warnings": [],
  "errors": []
}
```

4. **GATE G3**: If `success: false` → ERROR with script's error messages

### Phase 4: Generate Specification

1. **Load spec template**: `.specify/templates/spec-template.md`

2. **Generate spec content** using consolidated model:

   **User Scenarios section:**
   - Group user stories by actor/goal
   - Assign priorities based on:
     - Source weight (higher weight → higher priority consideration)
     - Frequency across sources (mentioned in multiple → higher priority)
     - Explicit priority markers in sources
   - Format as P1, P2, P3 with acceptance scenarios

   **Functional Requirements section:**
   - Merge requirements from all sources
   - Deduplicate similar requirements (keep higher-weight version)
   - Number as FR-001, FR-002, etc.
   - Include [CONFLICT] markers for unresolved items

   **Key Entities section:**
   - Merge entity definitions
   - Combine attributes from multiple sources
   - Note attribute conflicts if weights are close

   **Success Criteria section:**
   - Prefer specific metrics over vague ones
   - Merge overlapping criteria
   - Flag conflicting metrics

   **Edge Cases section:**
   - Aggregate from all sources
   - Deduplicate similar scenarios

   **Assumptions section:**
   - List all implicit decisions made during synthesis
   - Note which source informed each assumption
   - Include "Source weights used for conflict resolution" entry

3. **Add Synthesis Metadata** section (after title):

   ```markdown
   ## Synthesis Metadata

   **Generated**: {timestamp}
   **Sources**: {count} files
   **Conflicts Resolved**: {count} (auto: {auto_count}, manual: {manual_count})
   **Confidence**: {overall_confidence}%

   <details>
   <summary>Source Files</summary>

   | File            | Weight | Contribution                   |
   | --------------- | ------ | ------------------------------ |
   | requirements.md | 7.27   | User Stories, FR-001 to FR-005 |
   | arch-notes.md   | 4.44   | Entities, Constraints          |

   </details>
   ```

4. **Write spec** to SPEC_FILE

### Phase 5: Quality Validation

Same as `/speckit.specify` Phase 6:

1. **Create checklist** at `FEATURE_DIR/checklists/requirements.md`

2. **Validate against checklist**:
   - No implementation details
   - Requirements are testable
   - Success criteria are measurable
   - [CONFLICT] markers counted (warn if > 3)

3. **Handle [NEEDS CLARIFICATION]**:
   - If synthesis left gaps → create markers
   - Limit to 3 markers maximum
   - Present to user if any remain

4. **Handle [CONFLICT] markers**:
   - If `--strict` mode: list all conflicts for user resolution
   - If normal mode: conflicts already resolved by weight
   - Present remaining conflicts (if any) with options table

### Phase 6: Report & Handoff

1. **Output completion report**:

   ```markdown
   ## ✅ Specification Synthesized

   **Branch**: `007-feature-name`
   **Spec**: `specs/007-feature-name/spec.md`

   ### Synthesis Summary

   - Sources processed: 4
   - Conflicts auto-resolved: 3
   - Conflicts pending: 1 (see [CONFLICT] markers)
   - Overall confidence: 87%

   ### Source Contributions

   | Source                | Contributed                |
   | --------------------- | -------------------------- |
   | requirements.md (W:9) | 12 requirements, 3 stories |
   | arch.md (W:7)         | 5 entities, 2 constraints  |

   ### Next Steps

   - Review [CONFLICT] markers in spec
   - Run `/speckit.clarify` to resolve ambiguities
   - Or proceed to `/speckit.plan`
   ```

2. **Suggest next command** based on state:
   - If [CONFLICT] markers remain → suggest manual review
   - If [NEEDS CLARIFICATION] markers → suggest `/speckit.clarify`
   - If clean → suggest `/speckit.plan`

---

## Voice Weight Algorithm (Reference)

### Effective Weight Calculation

```
EffectiveWeight = ExplicitWeight × SignificanceScore × FreshnessMultiplier

Where:
- ExplicitWeight: User-specified 1-10 (default: 5)
- SignificanceScore: Auto-calculated 0.0-1.0
- FreshnessMultiplier: 0.8-1.0 based on file age
```

### Significance Score Calculation

```
SignificanceScore = Σ (criterion × weight)

Criteria:
- Completeness (0.25): Coverage of functional aspects
- Specificity (0.25): Concrete vs abstract statements
- Consistency (0.20): No internal contradictions
- Relevance (0.15): Direct feature applicability
- Structure (0.15): Formatting quality
```

### Conflict Resolution Rules

| Weight Differential | Action                               |
| ------------------- | ------------------------------------ |
| > 30%               | Auto-resolve to higher weight        |
| 10-30%              | Auto-resolve if specificity differs  |
| < 10%               | Create [CONFLICT] marker             |
| Any (with --strict) | Always create marker                 |
| ExplicitWeight = 10 | Always override (absolute authority) |

---

## Opus 4.5 Model Considerations

### Context Window Management

- **Load sources in order**: Process highest-weight sources first to establish strong baseline
- **Chunking for large sources**: If source > 50KB, extract structured sections only
- **Progressive refinement**: Build consolidated model incrementally

### Token Efficiency

- **Source map first**: Analyze all sources before synthesis to avoid re-reads
- **Structured extraction**: Use specific patterns (Given/When/Then, MUST/SHOULD) for targeted extraction
- **Conflict detection batch**: Identify all conflicts in single pass

### Hallucination Prevention

- **Provenance tracking**: Every spec element links to source file
- **No invention**: If information not in sources, mark as [NEEDS CLARIFICATION]
- **Weight transparency**: Log all conflict resolutions with rationale

---

## Error Handling

| Error                      | Response                                                                           |
| -------------------------- | ---------------------------------------------------------------------------------- |
| No sources found           | ERROR "No valid source files found. Provide file paths, folders, or search terms." |
| All sources empty          | ERROR "All source files are empty or unreadable."                                  |
| Git not initialized        | WARN "No git repo - skipping branch creation. Spec written to current directory."  |
| Weight out of range        | WARN "Weight {W} out of range, clamping to 1-10."                                  |
| Source file not found      | WARN "File not found: {path}, skipping."                                           |
| > 50% unresolved conflicts | WARN "High conflict rate ({N}%). Consider reviewing source consistency."           |
| Sources exceed limit       | ERROR "Too many sources ({N}). Max allowed: 15. Use --max-sources to adjust."      |
| Source file too large      | WARN "File {path} is {size}KB (>20KB). Consider splitting or using --single-pass." |

---

## Compatibility with speckit Flow

This command outputs **identical artifacts** to `/speckit.specify`:

- `specs/NNN-feature-name/spec.md` (same template structure)
- `specs/NNN-feature-name/checklists/requirements.md`

**Downstream commands work unchanged:**

- `/speckit.clarify` → processes [NEEDS CLARIFICATION] and [CONFLICT] markers
- `/speckit.plan` → reads spec.md as usual
- `/speckit.tasks` → parses user stories and requirements
- `/speckit.verify` → validates against spec requirements

**Additional metadata** (Synthesis Metadata section) is informational only and ignored by downstream commands.

---

## Known Limitations

### Token Budget Constraints

| Scenario          | Estimated Tokens | Risk                            |
| ----------------- | ---------------- | ------------------------------- |
| 3 sources × 5KB   | ~20K input       | ✅ Safe                         |
| 5 sources × 10KB  | ~60K input       | ⚠️ Monitor                      |
| 10 sources × 10KB | ~120K input      | 🔴 Quality degradation possible |

**Mitigations:**

- `--max-sources 10` enforced by default
- Large files (>20KB) trigger warning
- `--single-pass` reduces token usage by ~40%

### Claude Code Constraints

1. **No Parallel Execution**: All file reads are sequential
2. **Stateless Between Turns**: No resume if interrupted mid-synthesis
3. **Tool Call Overhead**: Each Read/Write = round-trip latency

### Provenance Limitations

- spec.md contains summary provenance (source list, conflict count)
- Element-level traceability via Synthesis Metadata section

---

## Open Questions (Requires Testing)

### Single-Pass vs Multi-Pass — REQUIRES BENCHMARKING

```
TRADEOFF:
- Single-pass: Faster, fewer tokens, may miss nuances
- Multi-pass: Thorough, more tokens, better for complex sources

TO VERIFY:
1. Test on 3 source complexity levels (simple/medium/complex)
2. Measure quality metrics:
   - Completeness of extracted requirements
   - Accuracy of conflict detection
   - User edit rate post-synthesis

RECOMMENDATION: Default to single-pass,
               offer --thorough flag for multi-pass
```

---

## Implementation Phases

### Phase 1: MVP (implement first)

- [x] Input syntax parsing (path:W:O) — `parse-sources.sh/.ps1`
- [x] Voice Weight Algorithm
- [x] Significance Score calculation
- [x] Basic conflict detection
- [x] Spec generation (template-compatible)
- [x] `--max-sources` limit enforcement — in `parse-sources.sh/.ps1`
- [x] Branch/directory setup — `synthesize-setup.sh/.ps1`
- [x] `--dry-run` mode — scripts + command flow documented
- [x] Multi-lens analysis for conflict resolution

### Phase 2: Optimizations (after MVP validated)

- [ ] Single-pass optimization
- [ ] Source map caching
- [ ] Checkpoint/recovery for long runs

### Utility Scripts Created

| Script                                             | Platform   | Purpose                                  |
| -------------------------------------------------- | ---------- | ---------------------------------------- |
| `.specify/scripts/bash/parse-sources.sh`           | Bash       | Parse source arguments, validate files   |
| `.specify/scripts/powershell/parse-sources.ps1`    | PowerShell | Parse source arguments, validate files   |
| `.specify/scripts/bash/synthesize-setup.sh`        | Bash       | Create branch, directories, init spec.md |
| `.specify/scripts/powershell/synthesize-setup.ps1` | PowerShell | Create branch, directories, init spec.md |

---

## Multi-Lens Analysis (Conflict Resolution)

For conflicts where Voice Weight alone is insufficient (weight differential < 30%), use structured multi-perspective analysis:

```markdown
## Conflict Analysis: {topic}

**Position A** ({source_a}, weight {weight_a}):
{content_a}

**Position B** ({source_b}, weight {weight_b}):
{content_b}

### Multi-Lens Evaluation

Analyze from each perspective (2-3 sentences each):

1. **Architecture**: Which is more extensible/maintainable?
2. **Testability**: Which is easier to test and verify?
3. **Security**: Are there security implications?
4. **User Value**: Which delivers more user value?

### Synthesis

Based on the above analysis and source weights:

- **Recommendation**: [A | B | Hybrid]
- **Rationale**: [1-2 sentences]
- **Confidence**: [0-100%]
```

**Characteristics:**

- ~500 tokens per conflict analysis
- Single LLM call with 4 perspectives
- Confidence threshold: ≥70% for auto-resolution
- Below threshold → creates [CONFLICT] marker for user
