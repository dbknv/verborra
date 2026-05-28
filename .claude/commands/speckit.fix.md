---
description: Fix issues found by speckit.verify with full context awareness and source of truth validation
handoffs:
  - label: Re-verify fixed issues
    agent: speckit.verify
    prompt: Re-verify the fixed issue
    send: true
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

**Supported arguments:**

- `--issue V001` — Fix specific issue
- `--batch US3` — Fix all issues in story
- `--dry-run` — Show what would be fixed without applying

## Language

All **produced project documentation** (new files you create or updates you write into markdown docs) MUST be written in **English**.

Source operational artifacts MUST remain in English:

- Commands (`.claude/commands/**`)
- Memory (`.specify/memory/**`)
- Document templates (`.specify/templates/**`)

Use these English sources as inputs, but when generating the actual output documents, write them in English.

Target specs MUST be written in English:

- Constitution (`.specify/memory/constitution.md`)
- Output specs (`specs/**`)

Do **NOT** translate product/service names, technology names, library/framework names, acronyms, or other proper technical terms—keep their original spelling (typically English).

## Outline

1. **Load Prerequisites**
   Run `.specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks` from repo root.
   Parse FEATURE_DIR. All paths must be absolute.
   For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").

2. **Load Issues from MCP Memory**
   MCP Memory is a semantic store with tags. Use tag-based search:

   ```
   issues = mcp_memory.search_by_tag(
       tags=["feature:{feature_id}", "speckit", "issues"],
       match_all=true
   )
   if not issues:
       ERROR: "Run /speckit.verify first to detect issues"
   ```

   Filter by arguments:
   - `--issue V001` → single issue
   - `--batch US3` → all issues where task is in US3
   - No filter → all issues with status "detected"

3. **Load Fix Context**
   MCP Memory is a semantic store. Use tag-based search:

   ```
   # Single search returns all fix-related memories
   memories = mcp_memory.search_by_tag(
       tags=["feature:{feature_id}", "speckit"],
       match_all=true
   )

   # Extract by memory_type
   sot_cache = memories.find(type="sot_cache")
   fix_history = memories.find(type="fix_decisions")
   project_knowledge = memories.find(type="project_patterns")
   ```

   **Latency**: Single search = 200-500ms (vs 900-1500ms sequential)

   Run `.specify/scripts/bash/collect-context.sh --issue V001 --feature-dir "$FEATURE_DIR"` to get:
   - Source of truth content
   - Files to modify
   - Related files (read-only)
   - Similar patterns in project

4. **Fix Decision Tree**

   ```
   Issue received
        │
        ▼
   ┌─────────────────────────────────────┐
   │ Source of Truth defined?            │
   └──────────────┬──────────────────────┘
            YES   │   NO
        ┌─────────┴─────────┐
        ▼                   ▼
   ┌─────────┐    ┌──────────────────────┐
   │ FIXABLE │    │ severity == CRITICAL? │
   └────┬────┘    └──────────┬───────────┘
        │              YES   │   NO
        │         ┌─────────┴─────────┐
        │         ▼                   ▼
        │    ┌─────────┐    ┌─────────────────┐
        │    │  BLOCK  │    │ PROMPT for spec │
        │    │ (human) │    │ update decision │
        │    └─────────┘    └────────┬────────┘
        │                        YES │ NO
        │                   ┌───────┴───────┐
        ▼                   ▼               ▼
   ┌─────────────┐   ┌───────────┐   ┌───────────┐
   │ CODE_FIX    │   │ SPEC_     │   │ FIX with  │
   │             │   │ UPDATE    │   │ TODO note │
   └─────────────┘   └───────────┘   └───────────┘
   ```

5. **Quality Gates (Check Before Fix)**

   | Gate           | Check                            | On Fail                |
   | -------------- | -------------------------------- | ---------------------- |
   | **Context**    | All required files loaded?       | HALT                   |
   | **Confidence** | >= 70%?                          | WARN, ask confirmation |
   | **Scope**      | Fix only touches affected_files? | HALT                   |
   | **Spec**       | Fix doesn't contradict spec?     | HALT                   |

6. **Apply Fix with Progress Streaming**

   ```
   🔧 Fixing V001: Missing edge case for empty input
   📋 Source of Truth: spec.md §FR-015
   📂 Files: parser.py, test_parser.py

   ⚙️ Analyzing fix approaches...
      Option 1: Add early return (confidence: 94%)
      Option 2: Throw custom exception (confidence: 72%)
      → Selected: Option 1

   ✏️ Applying fix to parser.py...
   ✏️ Adding test case to test_parser.py...
   ```

   If `--dry-run`: show changes without applying, then stop.

7. **Update Issue Status**

   ```
   issue.status = "fixed"
   issue.fix_attempts += 1
   issue.last_fix_attempt = now()

   mcp_memory.write("feature_{feature_id}_issues", issues)
   ```

8. **Save Fix Decision to History**

   ```
   mcp_memory.write("feature_{feature_id}_fix_decisions", {
     issue_id: {
       decision: "CODE_FIX",
       approach: "Added empty input handling",
       files_changed: ["parser.py", "test_parser.py"],
       timestamp: now(),
       confidence: 94
     }
   })
   ```

9. **Learn Pattern (if generalizable)**

   ```
   if is_common_pattern(fix):
       patterns = mcp_memory.read("project_knowledge")
       patterns.append({
         type: issue.type,
         fix_template: "if not value: return []",
         frequency: 1
       })
       mcp_memory.write("project_knowledge", patterns)
   ```

10. **Trigger Recheck**

    ```
    🔍 Running verification recheck...
    /speckit.verify --recheck V001
    ```

    If recheck fails:
    - Increment fix_attempts
    - If attempts >= 3: status = "blocked"
    - Otherwise: retry with different approach

11. **Update tasks.md Marker**
    If recheck passed:
    - Change `⚠️ ISSUE:V001` → `✅ VERIFIED`

12. **Output Summary**

    ```markdown
    ## Fix Result: V001

    **Status**: ✅ Fixed and verified
    **Approach**: Added empty input handling
    **Confidence**: 94%

    ### Changes Made

    | File           | Change                                  |
    | -------------- | --------------------------------------- |
    | parser.py      | +5 lines (early return for empty input) |
    | test_parser.py | +12 lines (2 test cases)                |

    ### Pattern Learned

    - Type: `missing_edge_case`
    - Template: `if not value: return []`
    ```

## Critical Rules

1. **No Source of Truth = No Silent Fix**
   - `source_of_truth.type == "none"` + severity >= high → BLOCK or PROMPT
   - Never invent behavior that isn't specified

2. **Anti-Hallucination**
   - If multiple fix paths exist, add `uncertainty.flags`
   - Always explain `why_this_fix` in output

3. **Atomic Changes**
   - One issue → one fix
   - If fix requires multiple issues, suggest splitting

4. **Rollback Ready**
   - Track all changes for potential rollback
   - If recheck fails 3 times → BLOCK

## Fix Decision Matrix

| source_of_truth.type | severity   | Action                                    |
| -------------------- | ---------- | ----------------------------------------- |
| spec/contract        | any        | **CODE_FIX** directly                     |
| interface            | any        | **CODE_FIX** to match interface           |
| test                 | any        | **CODE_FIX** or discuss test validity     |
| none                 | critical   | **BLOCK** — require spec update first     |
| none                 | high       | **WARN** — suggest spec update, allow fix |
| none                 | medium/low | **FIX** — add TODO comment for spec       |

## Spec Update Flow

When `source_of_truth.type === "none"` and severity >= high:

```markdown
## Spec Gap Detected

**Issue**: V001 - Missing edge case for empty input
**Problem**: Behavior for empty input is undefined

### Proposed Spec Addition

**Location**: spec.md §FR-015 (DSL Requirements)

**Add**:

> FR-015.3: The DSL parser MUST handle empty expressions by returning
> an empty result list.

### Options

1. **Accept** - Add to spec, then fix code
2. **Modify** - Edit proposed text, then add
3. **Reject** - Mark as WONT_FIX
4. **Defer** - Skip for now, create TODO

Your choice: [1/2/3/4]
```

## MCP Memory Entities

```typescript
// Read on start
feature_{id}_issues        // Issues to fix
source_of_truth_cache      // Spec references
feature_{id}_fix_decisions // Avoid repeating failed approaches
project_knowledge          // Patterns for similar fixes

// Write on complete
feature_{id}_issues        // Updated status
feature_{id}_fix_decisions // New fix decision
project_knowledge          // Learned pattern (if any)
```

## Fix Confidence Thresholds

- **>= 90%**: Fix without questions
- **70-89%**: Fix with WARNING
- **50-69%**: PROMPT for confirmation
- **< 50%**: BLOCK, insufficient context
