---
description: Verify implementation completeness of tasks marked [X] in tasks.md with risk-based verification levels and optional runtime smoke testing
handoffs:
  - label: Fix found issues
    agent: speckit.fix
    prompt: Fix all detected issues
    send: true
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

**Supported arguments:**

- `story:US3` — Scope to specific user story
- `phase:2` — Scope to specific phase
- `--deep` — Override: Deep verification for all tasks
- `--full` — Ignore cache, verify all from scratch
- `--recheck V001` — Re-verify specific issue after fix
- `--skip-graph` — Skip graph connectivity check
- `--smoke` — Run runtime smoke tests: curl endpoints from contracts/ to verify they return non-404
- `--smoke-url URL` — Override server base URL for smoke tests (default: auto-detect)
- `--smoke-auth "Header: value"` — Auth header for smoke tests (e.g. `--smoke-auth "Cookie: auth_token=eyJ..."`)

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

## Outline

1. **Load Prerequisites**
   Run `.specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks` from repo root.
   Parse FEATURE_DIR and AVAILABLE_DOCS. All paths must be absolute.
   For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").

2. **Parse Tasks**
   Run `.specify/scripts/bash/parse-tasks.sh --feature-dir "$FEATURE_DIR" --status completed --json`.
   This gives you structured JSON with:
   - `completed` tasks (marked `[X]`)
   - `by_risk` classification (critical, high, medium, low)
   - `stories` and `phases` grouping
   - `critical_paths` list

3. **Load MCP Memory State**
   MCP Memory is a knowledge graph with entities and observations. Use text search or exact name lookup:

   ```python
   # Option A: Get by exact entity names (preferred when names are known)
   entities = mcp_memory.open_nodes(names=[
       f"verify_{feature_id}_state",
       f"verify_{feature_id}_issues"
   ])

   state = next((e for e in entities if "state" in e.name), None)
   issues = next((e for e in entities if "issues" in e.name), None)

   # Option B: Text search for all related entities
   search_results = mcp_memory.search_nodes(query=f"verify {feature_id} speckit")

   # Parse observations (string arrays with key:value format)
   if state:
       for obs in state.observations:
           if obs.startswith("last_verified:"):
               last_verified = obs.split(":")[1]
   ```

   **Note**: Observations are string arrays, not JSON. Use `key:value` format.

   If `--full` flag: ignore state, verify all.
   If `--recheck V001`: load specific issue, verify only affected files.
   Otherwise: skip already verified tasks (unless spec/contracts changed).

4. **Determine Scope**
   Apply user arguments:
   - `story:US3` → filter to US3 tasks only
   - `phase:2` → filter to Phase 2 tasks only
   - No filter → all completed tasks

5. **Risk-Based Level Selection**
   For each task in scope, determine verification level:

   | Risk         | Markers                                                                    | Level       | Confidence |
   | ------------ | -------------------------------------------------------------------------- | ----------- | ---------- |
   | **CRITICAL** | `(critical path`, `100% coverage`, `security`, `auth`, `pii`, `rate_limit` | L4 Deep     | 95%        |
   | **STANDARD** | All other tasks                                                            | L2 Standard | 80%        |

   If `--deep` flag: use L4 for all tasks.

   > **Note**: L0/L1 levels removed — in practice, agent always reads files (L2+).
   > Simplified matrix reflects real behavior and guarantees 80%+ confidence.

6. **Execute Verification with Progress Streaming**
   For each task, output progress BEFORE checking:

   ```
   ⏳ Verifying T094 [L2 Standard]...
   ⏳ Verifying T095 [L4 Deep]...
   ```

   Then perform level-appropriate checks:

   **L2 Standard (80%)**:
   - Read file content
   - Verify structure matches task description
   - Check imports/exports exist
   - Basic logic review against task

   **L4 Deep (95%)**:
   - All L2 checks, plus:
   - Full logic review against spec
   - Edge case coverage verification
   - Security/compliance checks

   After check:
   - `✅` if passed
   - `⚠️ Issue found` if failed

7. **Create Issues for Failures**
   For each failed verification, create issue with schema:

   ```typescript
   {
     id: "V001",  // generate_issue_id()
     task_id: "T094",
     file: "/absolute/path/to/file.py",
     verification_level: "L4",  // L2 (80%) or L4 (95%)
     confidence: 87,
     confidence_required: 95,   // 80 for L2, 95 for L4
     severity: "high",
     type: "missing_edge_case",
     description: "Missing edge case for empty input",
     source_of_truth: {
       type: "spec",
       reference: "spec.md §FR-015",
       content: "DSL must handle empty expressions",
       confidence: 95
     },
     fix_context: {
       can_fix_automatically: true,
       suggested_approach: "Add empty check + test case",
       affected_files: ["parser.py", "test_parser.py"],
       requires_spec_update: false
     },
     status: "detected",
     uncertainty: {
       flags: [],
       confidence_reason: "Clear spec requirement, code missing check"
     }
   }
   ```

8. **Update tasks.md Markers**
   Add verification markers to completed tasks:
   - `✅ VERIFIED` — passed verification
   - `⚠️ ISSUE:V001` — has open issue
   - `🔲 PENDING` — not yet verified

9. **Save State to MCP Memory**

   ```python
   # Save verification state as entity with observations
   mcp_memory.create_entities(entities=[{
       "name": f"verify_{feature_id}_state",
       "entityType": "VerificationState",
       "observations": [
           f"last_verified:{datetime.now().isoformat()}",
           f"verified_tasks:{','.join(verified_task_ids)}",
           f"spec_hash:{spec_hash}",
           f"contracts_hash:{contracts_hash}",
           f"total_passed:{passed_count}",
           f"total_issues:{issues_count}",
           "speckit verify"  # searchable marker
       ]
   }])

   # Save issues registry
   issue_observations = [
       f"feature:{feature_id}",
       f"next_id:{next_issue_id}",
       f"last_updated:{datetime.now().isoformat()}",
       "speckit verify issues"
   ]
   for issue in issues:
       issue_observations.append(
           f"{issue.id}|task:{issue.task_id}|file:{issue.file}|severity:{issue.severity}|status:{issue.status}"
       )

   mcp_memory.create_entities(entities=[{
       "name": f"verify_{feature_id}_issues",
       "entityType": "IssuesRegistry",
       "observations": issue_observations
   }])
   ```

10. **Runtime Smoke Verification (if `--smoke` flag)**
    **GATE**: Skip this step entirely if `--smoke` was not provided.

    This phase verifies that API endpoints declared in `contracts/` are **actually reachable at runtime**, catching issues invisible to static analysis: stale `dist/` build artifacts, missing codegen (`prisma generate`), broken workspace package wiring.

    **10a. Extract Endpoints from Contracts**
    Read ALL files in `{FEATURE_DIR}/contracts/`. Parse endpoints:

    **OpenAPI YAML** (`.yaml`, `.yml`): find `paths:` section, extract method + path.
    Alternatively run `contract-check.sh --contracts-dir "{FEATURE_DIR}/contracts" --source-dir "$SRC_DIR" --output json` and parse its `endpoints` array — this reuses the existing script.

    **Markdown** (`.md`): look for endpoint patterns in headers (`### GET /api/...`), inline bold (`**POST** \`/api/...\``), curl examples, tables.

    **Skip**: `.ts`, `.js` files (type definitions, not endpoint docs).

    Deduplicate by `method + path`. Output progress:

    ```
    📋 Smoke: extracted 11 endpoints from contracts/
    ```

    **GATE**: If no endpoints found → skip smoke phase with message:

    ```
    ⏭️ Smoke: no parseable endpoints in contracts/ — skipping runtime checks
    ```

    **10b. Detect Base URL**
    Priority order:
    1. `--smoke-url` argument (highest priority)
    2. `CLAUDE.md` — search for `http://localhost:PORT`, `API_URL`, `BASE_URL`
    3. `docker-compose.yml` / `docker-compose.dev.yml` — backend service port mapping
    4. `.env` / `.env.local` — `API_URL`, `BACKEND_URL`
    5. `package.json` proxy field
    6. Default: `http://localhost:3001`

    **10c. Health Check**

    ```bash
    curl -s -o /dev/null -w "%{http_code}" $BASE_URL/health
    ```

    If connection refused / timeout:

    ```
    ❌ Smoke: server not reachable at {BASE_URL}
    Start the dev server and re-run with --smoke
    ```

    **GATE**: Skip smoke phase (do NOT stop entire verify — static results are still valid). Continue to step 11.

    **10d. Execute Smoke Tests**
    For each endpoint, send a minimal request:

    | Method         | Body              | Expected non-404   |
    | -------------- | ----------------- | ------------------ |
    | GET            | none              | Any status         |
    | POST/PATCH/PUT | `{}` (empty JSON) | 400/401/422 = PASS |
    | DELETE         | none              | Any status         |

    **Path parameters**: Replace `{id}`, `{slug}` etc. with `00000000-0000-0000-0000-000000000000` (UUID).

    ```bash
    curl -s -o /tmp/smoke_response.json -w "%{http_code}" \
      -X {METHOD} "{BASE_URL}{PATH}" \
      -H "Content-Type: application/json" \
      [-H "{SMOKE_AUTH}"] \
      [-d '{}']
    ```

    **Classify response:**

    | Status                     | Classification | Meaning                                         |
    | -------------------------- | -------------- | ----------------------------------------------- |
    | 404 + "Cannot POST/GET..." | 🔴 FAIL        | Route NOT registered                            |
    | 000 / timeout              | 🔴 FAIL        | Connection error                                |
    | 500                        | 🟡 WARN        | Route exists but crashes (stale deps? codegen?) |
    | 401/403                    | 🟢 PASS        | Route exists, auth works                        |
    | 400/422                    | 🟢 PASS        | Route exists, validation works                  |
    | 200/201/204                | 🟢 PASS        | Fully functional                                |

    **IMPORTANT**: Distinguish framework 404 (`Cannot POST /api/...` in HTML) from application 404 (`{"title":"Not Found"}` in JSON) — the latter is a PASS.

    Execute **sequentially** (not in parallel). Timeout: 10 seconds per request.

    Progress streaming:

    ```
    ⏳ Smoke: GET  /api/admin-settings/employees ...
    ✅ Smoke: GET  /api/admin-settings/employees → 200
    🔴 Smoke: POST /api/admin-settings/employees → 404 (Cannot POST)
    🟡 Smoke: GET  /api/admin-settings/employees/{id} → 500 (findFirst undefined)
    ```

    **10e. Diagnose Failures**
    For each 🔴 FAIL:
    - Search codebase for route handler matching the path
    - If found in source but 404 at runtime → **build/wiring issue** (stale dist, missing import)
    - Check barrel exports: trace import chain `route file → module index → app entry point`
    - Check `package.json` `exports` field of workspace packages → if pointing to `./dist/*`, check if dist is stale

    For each 🟡 WARN (500):
    - Read response body for error patterns:
      - `Cannot read properties of undefined (reading 'findFirst')` → **Prisma not generated**
      - `MODULE_NOT_FOUND` → **missing dependency**
      - `is not a function` → **stale build / wrong exports**
      - `ECONNREFUSED :5432` → **missing external service**
      - `relation "X" does not exist` → **migration not applied**

    **10f. Create Issues for Smoke Failures**
    Use the same issue schema (V-prefix, same registry) as static issues. New issue types:

    | Type                    | Description                                                            |
    | ----------------------- | ---------------------------------------------------------------------- |
    | `smoke_route_not_found` | Endpoint returns framework 404 — route not registered                  |
    | `smoke_runtime_error`   | Endpoint returns 500 — runtime crash                                   |
    | `smoke_build_wiring`    | Route exists in source but not at runtime — stale build/broken imports |
    | `smoke_codegen_stale`   | Error indicates missing codegen (prisma, OpenAPI client)               |

    ```typescript
    {
      id: "V018",
      task_id: null,  // smoke issues map to endpoints, not tasks
      endpoint: "POST /api/admin-settings/employees",
      file: "packages/backend/modules/admin-settings/src/employees/employees.router.ts",
      verification_level: "SMOKE",
      confidence: 100,  // HTTP status is a fact, not opinion
      confidence_required: 100,
      severity: "critical",
      type: "smoke_build_wiring",
      description: "POST /api/admin-settings/employees returns 404. Route handler exists in employees.router.ts but package.json exports point to stale dist/",
      source_of_truth: {
        type: "contract",
        reference: "contracts/employees-api.yaml",
        content: "POST /api/admin-settings/employees",
        confidence: 100
      },
      fix_context: {
        can_fix_automatically: true,
        suggested_approach: "Rebuild dist or update package.json exports to ./src/index.ts",
        affected_files: ["packages/backend/modules/admin-settings/package.json"],
        requires_spec_update: false
      },
      status: "detected"
    }
    ```

11. **Graph Verification (Dead Code Detection)**
    Run universal graph check to detect unused exports and imports:

    ```bash
    .specify/scripts/bash/graph-check.sh "$FEATURE_DIR" "$SRC_DIR" --mode=universal
    ```

    Parse JSON output. For each issue:
    - `graph_unused_export` — function/class exported but never imported (severity: high)
    - `graph_imported_not_used` — imported but never actually used (severity: high)

    Create verification issues for each finding.

    **Supported stacks**: `.ts`, `.tsx`, `.py`, `.go`

    **Note**: For UI-specific checks (modal triggers), use `speckit.verify-ui`.

12. **Output Summary Report**
    Generate report using template `.specify/templates/verification-report-template.md`.
    Save to `specs/{feature}/verification/report.md`.

    Also update `specs/{feature}/verification/issues.md` using
    `.specify/templates/verification-issues-template.md`.

    Example output (with smoke):

    ```markdown
    ## Verification Report: {scope}

    Generated: {timestamp} | Feature: {feature_id}

    ### Summary

    | Level         | Tasks | Passed | Issues | Confidence |
    | ------------- | ----- | ------ | ------ | ---------- |
    | Deep (L4)     | 5     | 4      | 1      | 95%        |
    | Standard (L2) | 12    | 12     | 0      | 80%        |
    | **Total**     | 17    | 16     | 1      | 84%        |

    ### Smoke Test Results

    | #   | Method | Path                               | Status | Result  |
    | --- | ------ | ---------------------------------- | ------ | ------- |
    | 1   | GET    | /api/admin-settings/employees      | 200    | 🟢 PASS |
    | 2   | POST   | /api/admin-settings/employees      | 404    | 🔴 FAIL |
    | 3   | GET    | /api/admin-settings/employees/{id} | 500    | 🟡 WARN |

    Smoke: 8 PASS / 1 WARN / 2 FAIL (11 endpoints)

    ### Issues Found

    | ID   | Task | File                | Type               | Severity |
    | ---- | ---- | ------------------- | ------------------ | -------- |
    | V001 | T094 | test_parser.py      | missing_edge_case  | high     |
    | V018 | —    | employees.router.ts | smoke_build_wiring | critical |

    ### Next Actions

    - Run `/speckit.fix --issue V001` to fix with full context
    ```

    **Handoff to verify-ui**: If `ui/*.md` files exist in feature directory, suggest:

    ```
    💡 UI specs detected. Run /speckit.verify-ui for visual/props/states verification.
    ```

## Critical Rules

1. **Anti-Hallucination**: If confidence < 80%, add `[UNCERTAIN]` to description and escalate to L4 if possible
2. **Source of Truth**: Never invent SOT — if not found, `type: "none"`
3. **Progress Streaming**: Output status for EVERY task before checking
4. **Incremental**: Use MCP Memory to skip already-verified (unless `--full`)
5. **Smoke: Never auto-start servers**: If server is not running, skip smoke phase — do NOT run `docker compose up` or `npm run dev`
6. **Smoke: Never send destructive real data**: Use empty bodies `{}` and fake UUIDs `00000000-...` for path params
7. **Smoke: Sequential execution**: Run curl requests one at a time — some endpoints may have side effects
8. **Smoke: Distinguish 404 types**: Framework 404 (HTML "Cannot POST") = FAIL. Application 404 (JSON "Not found") = PASS

## Verification Level Details

### L2: Standard (80% confidence)

- **What agent does**: Read file → analyze content → verify against task
- **Checks performed**:
  - File exists and is non-empty
  - Code structure matches task description
  - Imports/exports are valid
  - Basic logic review
- **Guarantee**: Implementation matches task requirements
- **Use for**: All standard tasks (default level)

### L4: Deep (95% confidence)

- **What agent does**: Full logic review against spec, edge cases, compliance
- **Checks performed**:
  - All L2 checks, plus:
  - Edge case coverage
  - Error handling completeness
  - Security considerations
  - Spec requirement traceability
- **Guarantee**: Behavior matches spec, production-ready
- **Use for**: Critical paths, security, auth, 100% coverage tasks

### SMOKE: Runtime (100% confidence)

- **What agent does**: HTTP requests to endpoints declared in contracts/
- **Checks performed**:
  - Endpoint reachable (non-404)
  - No runtime crash (non-500)
  - Route handler actually mounted in app
  - Build artifacts up to date
  - Codegen artifacts current (Prisma, OpenAPI)
- **Guarantee**: Endpoint exists at runtime, not just in source code
- **Requires**: Running dev server, `--smoke` flag
- **Use for**: All API endpoints from contracts/

## Integration Task Verification

**CRITICAL**: Tasks containing keywords like "integrate", "connect", "use in", "add to page" require **semantic verification**, not just file existence checks.

### Detection

Task is an integration task if description contains:

- "integrate"
- "add to"
- "use in"
- "connect"
- "all components"

### Integration Verification Checklist

For each integration task:

- [ ] **Identify target** — find file mentioned in task (e.g., `KnowledgeBasePage`)
- [ ] **Find component index** — locate `index.ts` that exports components to integrate
- [ ] **Verify imports** — each exported component is imported in target file
- [ ] **Verify usage** — each imported component appears in JSX/render (not just imported)
- [ ] **Check TODO markers** — no `// TODO` comments related to integration
- [ ] **Check placeholders** — no `JSON.stringify()`, "Coming soon", empty handlers

**Fallback**: If no component index exists, verify imports from each component file directly.

**Example** — Task: "T090 Integrate all components into KnowledgeBasePage"

1. Target: `pages/knowledge-base/[pageId].tsx`
2. Components: exports from `ui/knowledge-base/index.ts` → `TreeView`, `PageEditor`, `SaveIndicator`
3. Check: all 3 imported? all 3 in JSX? no `// TODO: Replace with PageEditor`?

### Integration Issue Types

| Type                         | Description                      | Example                                     |
| ---------------------------- | -------------------------------- | ------------------------------------------- |
| `integration_missing_import` | Component not imported           | PageEditor not imported                     |
| `integration_unused_import`  | Imported but not used            | SaveIndicator imported but not in JSX       |
| `integration_todo_marker`    | TODO indicates incompleteness    | `// TODO: Replace with PageEditor`          |
| `integration_placeholder`    | Placeholder code instead of real | `JSON.stringify(content)` instead of Editor |
| `integration_partial`        | Only some components integrated  | TreeView yes, PageEditor no                 |

### Integration Issue Example

```typescript
{
  id: "V015",
  task_id: "T090",
  file: "/frontend/src/pages/knowledge-base/[pageId].tsx",
  verification_level: "L2",
  confidence: 95,
  confidence_required: 80,
  severity: "high",
  type: "integration_todo_marker",
  description: "TODO marker indicates incomplete integration: '// TODO: Replace with PageEditor component'",
  source_of_truth: {
    type: "task",
    reference: "tasks.md T090",
    content: "Integrate all components into KnowledgeBasePage",
    confidence: 100
  },
  fix_context: {
    can_fix_automatically: true,
    suggested_approach: "Replace JSON.stringify(content) with <PageEditor content={content} />",
    affected_files: ["[pageId].tsx"],
    requires_spec_update: false
  },
  status: "detected"
}
```

### Integration Red Flags (Auto-fail)

- `// TODO` referencing integration target
- `JSON.stringify()` for content that should be rendered
- Placeholder text: "Coming soon", "Not implemented"
- Console.log instead of actual functionality
- Empty handlers: `onClick={() => {}}`

## UI Component Verification

**Note**: For UI-specific verification use `speckit.verify-ui.md`.

verify-ui handles:

- Graph connectivity (dead code detection via `graph-check.sh`)
- Props/States verification against ui/\*.md
- Visual verification (Figma markers)
- Negative Specs verification
- Design System Manifest checks

## MCP Memory Entities

> **VERIFIED API** — Uses actual MCP Memory knowledge graph API.

```
Entity naming convention:
verify_{feature_id}_state       // Verification state (last run, hashes)
verify_{feature_id}_issues      // Issues registry with next_id counter

Observations format (string arrays):
- "last_verified:2026-01-28T10:30:00Z"
- "verified_tasks:T001,T002,T003"
- "V001|task:T094|file:parser.py|severity:high|status:detected"
```

## Issue ID Generation

```python
def generate_issue_id(feature_id: str) -> str:
    # Get issues registry entity by exact name
    try:
        result = mcp_memory.open_nodes(names=[f"verify_{feature_id}_issues"])
        if result.entities:
            # Parse next_id from observations
            for obs in result.entities[0].observations:
                if obs.startswith("next_id:"):
                    next_id = int(obs.split(":")[1])
                    return f"V{str(next_id).zfill(3)}"
    except:
        pass
    return "V001"  # First issue
```
