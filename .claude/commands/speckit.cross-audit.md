---
description: Perform cross-feature dependency and conflict analysis across multiple feature specs.
handoffs:
  - label: Run Expert Debates
    agent: speckit.debate
    prompt: "Run debates on the cross-audit findings. Mode: cross"
    send: true
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).
User input should contain feature numbers to audit (e.g., `005 007 008 009`, `005-009`, `*`).

## Language

All **produced project documentation** (new files you create or updates you write into markdown docs) MUST be written in **Russian**.

Source operational artifacts MUST remain in English:
- Commands (`.claude/commands/**`)
- Memory (`.specify/memory/**`)
- Document templates (`.specify/templates/**`)

Do **NOT** translate product/service names, technology names, library/framework names, acronyms, or other proper technical terms—keep their original spelling.

## Goal

Analyze cross-feature dependencies, conflicts, overlapping functionality, and pattern drift across N feature specifications. Output a structured `cross-audit.md` documenting all findings with code evidence.

## Operating Constraints

- Output is written to `FEATURE_DIR/cross-audit.md`
- Each finding MUST include `file:line` evidence from the actual codebase
- Findings without code evidence are marked [UNVERIFIED] and ranked lower

## Execution Steps

### 1. Setup

Run `.specify/scripts/bash/cross-audit-setup.sh --json <feature-numbers>` from repo root. Parse JSON for:
- `REPO_ROOT`, `CURRENT_BRANCH`, `FEATURE_DIR`
- `AUDIT_TARGETS[]` — array of feature objects with paths
- `WARNINGS[]` — any setup warnings

If `AUDIT_TARGETS` is empty or has fewer than 2 entries, abort with error: "Cross-audit requires at least 2 features."

### 2. Load Memory

Search MCP Memory for prior cross-audit results:
```
mcp_memory.search_nodes("cross-audit")
```

If found, use prior dependency graph as baseline to detect NEW findings vs previously known.

### 3. Load Feature Artifacts

For each target in `AUDIT_TARGETS`:
1. Read `spec.md` (required — already validated by setup script)
2. Read `plan.md` if `has_plan: true`
3. Read `data-model.md` if `has_data_model: true`
4. Skim `research.md` headers if `has_research: true`

Extract from each:
- **Entities**: database tables, models, types mentioned
- **FK relationships**: foreign keys, references between entities
- **API endpoints**: routes, controllers
- **Frontend state**: query keys, stores, shared hooks
- **Patterns used**: S3 handling, cache invalidation, error handling, soft-delete

### 4. Build Dependency Graph

Cross-reference extracted data to identify:

**Shared Entities** — same entity appears in multiple features:
- Table name matches across data-model.md / schema references
- DTO types shared across feature boundaries

**FK Cross-Feature** — foreign key from one feature's entity to another's:
- `employees.positionId → positions` (008 → 007)
- `employees.departmentId → departments` (008 → 009)

**Shared Services** — same backend service/utility used across features:
- S3 service patterns, email service, etc.

**Shared Frontend State** — query keys, stores referenced across modules:
- `DEPARTMENTS_KEY` used in departments module AND positions module

### 5. Detect Conflicts

For each cross-feature relationship, check for:

**CONFLICT** — contradictory decisions:
- Different `onDelete` strategies for the same FK
- Different error handling for the same error type
- Incompatible DTO types for the same entity

**OVERLAP** — duplicated functionality:
- Same query/function implemented in multiple modules
- Same API endpoint logic duplicated

**DRIFT** — same problem solved differently:
- One feature uses presigned URLs, another uses public URLs
- One feature has application guard, another relies on DB constraint

**DEPENDENCY** — implicit coupling:
- Feature A assumes Feature B's data model unchanged
- Frontend cache keys not invalidated cross-feature

### 6. Verify in Code

For each finding, use Grep and Read to find **concrete evidence**:
- Exact `file:line` with code quote
- If evidence not found → mark [UNVERIFIED]

This step is MANDATORY. Findings based purely on spec analysis without code verification are second-class.

### 7. Classify and Rank

Assign each finding:
- **Type**: CONFLICT | OVERLAP | DRIFT | DEPENDENCY
- **Severity**: CRITICAL | HIGH | MEDIUM | LOW
  - CRITICAL: contradictory FK constraints, data corruption risk
  - HIGH: duplicated logic with divergent behavior, missing cross-cache invalidation
  - MEDIUM: pattern drift, type mismatches covered by structural typing
  - LOW: cosmetic inconsistencies, naming conventions

### 8. Save to Memory

```
mcp_memory.create_entities([{
  name: "cross-audit:{branch}",
  entityType: "cross-audit",
  observations: [
    "features: {feature_list}",
    "conflicts: {count}",
    "overlaps: {count}",
    "drifts: {count}",
    "dependencies: {count}",
    "date: {ISO date}"
  ]
}])
```

### 9. Write Output

Load `.specify/templates/cross-audit-template.md` and fill all sections. Write to `FEATURE_DIR/cross-audit.md`.

### 10. Report

Output summary to user:

```
═══ Cross-Feature Audit Complete ═══
Features analyzed: N
Findings: M total (C critical, H high, M medium, L low)
  CONFLICT: N
  OVERLAP: N
  DRIFT: N
  DEPENDENCY: N

Written to: {FEATURE_DIR}/cross-audit.md
Next: /speckit.debate --cross
```

## Context

$ARGUMENTS
