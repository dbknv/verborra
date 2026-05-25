---
description: Evaluate debate verdicts into ROI matrix, implementation order, and spec update recommendations.
handoffs:
  - label: Update Spec
    agent: speckit.specify
    prompt: "Update spec based on evaluation recommendations"
  - label: Generate Tasks
    agent: speckit.tasks
    prompt: "Generate tasks from evaluation recommendations"
    send: true
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

Do **NOT** translate product/service names, technology names, library/framework names, acronyms, or other proper technical terms—keep their original spelling.

## Goal

Transform `debates.md` verdicts into an actionable evaluation report:
- ROI matrix comparing all decisions
- Implementation order grouped into PRs by file proximity
- Spec sections that need updating
- Known Blockers requiring immediate attention

## Operating Constraints

- Input: `debates.md` from current feature dir (produced by `/speckit.debate`)
- Output: `evaluation.md` in the same feature dir
- READ debates.md — do NOT modify it
- WRITE evaluation.md — new file

## Execution Steps

### 1. Load Artifacts

Run `.specify/scripts/bash/check-prerequisites.sh --json --paths-only` to get FEATURE_DIR.

Load:
- `FEATURE_DIR/debates.md` (required — abort if missing, suggest running `/speckit.debate` first)
- `FEATURE_DIR/spec.md` (required)
- `FEATURE_DIR/plan.md` (optional, for tech context)

### 2. Extract Verdicts

Parse `debates.md` for:
- Each `DEBATE-N` block: verdict, priority score, category, confidence, parameter scores
- Known Blockers section
- Summary Matrix

Build a structured list:
```
[
  { id: "DEBATE-1", title: "...", verdict: "CHANGE", priority: 4.2, category: "LOUD_FAILURE", confidence: "HIGH", effort_loc: 20, files: [...] },
  ...
]
```

### 3. Build ROI Matrix

For each verdict with CHANGE or DEFER:

```
ROI = Priority_Score / Effort_Normalized
  where Effort_Normalized = max(1, LOC / 50)
```

Sort by ROI descending. Higher ROI = fix first (high priority, low effort).

Output table:
```
| # | Fix | Severity | Effort (LOC) | QA visibility | Category | Priority | Confidence | ROI |
```

### 4. Group into PRs

Cluster fixes by file proximity:
- Fixes touching the same file(s) → same PR
- Backend-only fixes → one PR
- Frontend-only fixes → one PR
- Mixed (backend + frontend + migration) → assess if separable

For each PR:
- List contained DEBATE-N items
- List files affected
- Estimate total effort
- Assess regression risk
- Explain why this PR order (dependency, ROI, risk)

### 5. Identify Spec Updates

For each verdict = CHANGE:
- Identify which section of spec.md needs updating
- Draft a 1-line summary of what should change
- Reference the DEBATE-N source

Output table:
```
| Section | Current Text (excerpt) | Proposed Change | Source (DEBATE-N) |
```

### 6. Handle Known Blockers

Copy Known Blockers from debates.md. For each:
- Confirm it's still valid (quick code check)
- Add recommended fix action
- Mark priority: IMMEDIATE (before any other PR)

### 7. Assess Review Items

Items with Confidence = MEDIUM are marked [REVIEW]. For each:
- Explain what additional context would raise confidence to HIGH
- Suggest specific questions for the user or code areas to investigate

Items with Confidence = LOW should have been caught by debate pauses. If any remain:
- Flag prominently
- Do NOT include in implementation order until resolved

### 8. Save to Memory

```
mcp_memory.create_entities([{
  name: "evaluation:{branch}",
  entityType: "evaluation",
  observations: [
    "total_debates: N",
    "verdicts_change: M",
    "verdicts_accepted: K",
    "prs_recommended: J",
    "blockers: L",
    "date: {ISO date}"
  ]
}])
```

### 9. Write Output

Load `.specify/templates/evaluation-template.md` and fill all sections. Write to `FEATURE_DIR/evaluation.md`.

### 10. Report

```
═══ Decision Evaluation Complete ═══
Debates evaluated: N
  CHANGE: M → grouped into K PRs
  ACCEPT: J (no action needed)
  DEFER: L (backlog)

Known Blockers: B (fix immediately)
[REVIEW] items: R (need additional context)

Recommended order:
  1. [Known Blockers] — immediate
  2. PR 1: [scope] — [reason]
  3. PR 2: [scope] — [reason]
  ...

Written to: {FEATURE_DIR}/evaluation.md
Next: /speckit.specify (update spec) or /speckit.tasks (generate tasks)
```

## Context

$ARGUMENTS
