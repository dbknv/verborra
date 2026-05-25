---
description: Run multi-round expert debates on spec decisions with code research, user calibration, and algorithmic verdict.
handoffs:
  - label: Evaluate Decisions
    agent: speckit.evaluate
    prompt: "Evaluate the debate verdicts and produce ROI matrix"
    send: true
  - label: Update Spec
    agent: speckit.specify
    prompt: "Update spec based on debate verdicts marked CHANGE"
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

**Sub-flow detection** from arguments:
- No arguments → **single** mode (current feature)
- Feature numbers (e.g., `005 007 008`) → **per-feature** mode (iterate each)
- `--cross` flag or handoff from cross-audit → **cross** mode (cross-feature findings)

## Language

All **produced project documentation** (new files you create or updates you write into markdown docs) MUST be written in **English**.

Source operational artifacts MUST remain in English:
- Commands (`.claude/commands/**`)
- Memory (`.specify/memory/**`)
- Document templates (`.specify/templates/**`)

Do **NOT** translate product/service names, technology names, library/framework names, acronyms, or other proper technical terms—keep their original spelling.

## Goal

Conduct structured multi-round expert debates on decisions made in specifications. Generate a `debates.md` document with:
- Expert arguments grounded in code evidence
- Practitioner calibration against real-world constraints
- Algorithmic verdict with transparent scoring and confidence assessment
- Actionable recommendations

## Operating Constraints

- Every expert argument MUST include `file:line` + code quote. Without code evidence → [UNVERIFIED]
- The judge uses a FORMULA, not intuition. All scores are explained
- RUNTIME_BLOCKERs (app won't start / crash on first click) are NOT debated — listed in Known Blockers
- Between rounds, the command MAY pause to ask the user for context
- Quality of analysis takes priority over token efficiency

## Expert Roles (FIXED)

### Theorists (Round 2)

| Role | Alias | Focus | Asks |
|------|-------|-------|------|
| **Architect** | ARCH | System architecture, coupling, cohesion, patterns | "Is this maintainable? Does it scale? Is coupling acceptable?" |
| **DBA** | DBA | Data model, migrations, constraints, indexes, query perf | "Is the schema correct? Are constraints consistent? Will queries perform?" |
| **Security** | SEC | Authentication, authorization, data exposure, OWASP | "Is data protected? Are there exposure vectors? OWASP compliance?" |

### Practitioners (Round 3)

| Role | Alias | Focus | Asks |
|------|-------|-------|------|
| **Tech Lead** | PRAGMA | Scope, effort/value tradeoff, delivery speed, pragmatism | "Is this worth fixing now? What's the real-world effort? MVP vs prod?" |
| **QA Mindset** | QA | Detectability, probability, regression risk | "Will a manual smoke test catch this? How likely is this in practice?" |

### Judge (Round 5)

Algorithmic evaluation. Not a "role" — a decision procedure with a formula.

## Execution Steps

### 0. Determine Sub-flow

Parse `$ARGUMENTS`:
- Empty → **single**: debate decisions in current feature's spec.md + plan.md
- Numbers (e.g., `005 007 008`) → **per-feature**: for each number, find feature dir and run full debate. Output: `debates-{NNN}.md` in each feature dir
- `--cross` → **cross**: read `cross-audit.md` from current feature dir, debate its findings

For **per-feature** mode, iterate the full R1–R5 sequence for each feature independently.

### ROUND 1: Context Gathering (automatic, no opinions)

**1.1 Memory Load**
```
mcp_memory.search_nodes("debate-pattern")
```
If found, extract prior decisions on similar topics (FK constraints, cache invalidation, S3 patterns) to use as precedents.

**1.2 Load Artifacts**

| Mode | Load |
|------|------|
| single | spec.md, plan.md, research.md (if exists) from current feature |
| per-feature | spec.md, plan.md from target feature |
| cross | cross-audit.md + spec.md/plan.md from all referenced features |

**1.3 Technology Docs (Context7)**

Extract key technologies from plan.md (e.g., Prisma, TanStack Query, S3). For each:
```
mcp_context7.resolve-library-id(libraryName: "prisma", query: "onDelete behavior")
mcp_context7.query-docs(libraryId: "/prisma/prisma", query: "onDelete Restrict vs SetNull behavior")
```
Cache results for use in R2-R4.

**1.4 Figma (if UI decisions in scope)**

If spec mentions UI components, forms, or dialogs:
```
mcp_figma.get_screenshot(nodeId: "...", fileKey: "...")
```

**1.5 Code Scan**

Use Grep/Read to load key source files mentioned in spec:
- Schema files (Prisma schema, migrations)
- Service files (business logic)
- Frontend hooks (state management)
- API routes (endpoints)

**1.5b Infrastructure Scan (if security, config, or deployment topics are in scope)**

Decisions about env vars, secrets, CORS, auth tokens, or any config-driven behavior CANNOT be evaluated from source code alone. The real runtime value is determined by the deployment pipeline, not by code defaults.

Scan for and load:
- CI/CD configs (`.gitlab-ci.yml`, `.github/workflows/*.yml`, `Jenkinsfile`)
- Docker compose files (`docker-compose*.yml`) — ALL variants (dev, prod, staging)
- Environment templates (`.env.*.example`, `.env.example`)
- Reverse proxy configs (`nginx.conf`, `traefik.yml`, `Caddyfile`)
- Infrastructure-as-code (`terraform/`, `k8s/`, `helm/`)

For each env var under debate, trace the **full delivery chain**:
1. Where is it defined? (CI/CD variables, `.env` file, compose `environment:` block)
2. What happens if it's missing? (default in code, empty string from shell, crash)
3. Is the code default reachable in any real deployment path?

This prevents false positives where code-level defaults appear dangerous but are unreachable in practice.

**1.6 Output progress**
```
=== ROUND 1/5: Context Gathering ===
- Memory: loaded N debate-pattern precedents
- Context7: [library] docs ([version])
- Figma: [N mockups loaded] (or "not required")
- Code: read N files ([list])
- Infrastructure: read N files ([list]) (or "not required")
- Context package ready. Found M decisions to analyze.
```

### ROUND 2: Theorists — Problem Identification

For each decision/approach found in spec + plan:

**2.1 Each expert analyzes independently**

ARCH evaluates: architecture, coupling, pattern consistency
DBA evaluates: data model, constraints, migration correctness
SEC evaluates: security, data exposure, authorization gaps

**2.2 Evidence requirement**

Each argument MUST include:
```
**[ROLE]**: [argument statement]
Evidence: `file.ts:42` — `exact code quote here`
```

Arguments without `file:line` are marked **[UNVERIFIED]** and will be deprioritized by the judge.

Use Grep and Read actively during argumentation to find evidence.

**2.3 Classify each decision**

- **CONTESTED**: experts disagree or identify a problem → goes to R3-R4
- **UNANIMOUS**: all experts agree the decision is correct → skip to summary
- **UNVERIFIED**: argument made but no code evidence → will be reviewed by practitioners

**2.4 Output progress**
```
=== ROUND 2/5: Theorists ===

-- R2 Summary --
Analyzed: N decisions
  CONTESTED: M (require debate)
  UNANIMOUS: K (experts agree — decision is correct)
  UNVERIFIED: J (no evidence in code)

Contested decisions:
  DEBATE-1: [title]  [ROLE vs ROLE]
  DEBATE-2: [title]  [ROLE concern]
  ...
```

**2.5 PAUSE CONDITION**

If fewer than 3 CONTESTED decisions found, OR if insufficient context for analysis:

Ask the user (using the clarify pattern — one question, recommended answer, options):
```
Found [N] contested decisions. Do you want to:
[A] Continue with the findings (recommended)
[B] Add specific questions for the debate
[C] Provide additional context
```

### ROUND 3: Practitioners — Reality Calibration

For each CONTESTED decision:

**3.1 PRAGMA (Tech Lead) evaluates**:
- **Stage**: MVP / production / scale — impacts acceptable tech debt level
- **Effort**: estimated LOC + files affected
- **6-month projection**: what happens if we postpone this fix?
- **Existing pattern**: is there a working solution in the codebase already? (use Grep to find)

**3.2 QA Mindset evaluates**:
- **QA Test**: describe concrete manual smoke test steps to reproduce
- **Detectability**: found immediately (basic smoke) / delayed (hours+) / specific scenario / invisible
- **Probability**: daily / monthly / yearly / theoretical — how often in real usage?
- **User-facing impact**: crash / wrong data / UX friction / cosmetic / invisible

**3.3 Practitioners MAY**:
- **Remove** [UNVERIFIED] issues with justification ("no code evidence, theoretical concern")
- **Downgrade** severity with justification ("QA will catch this on first test", "edge case <0.1%")
- **Upgrade** severity if they find NEW evidence practitioners noticed that theorists missed

**3.4 Output progress**
```
=== ROUND 3/5: Practitioners ===

-- R3 Summary --
  Removed: J (UNVERIFIED without confirmation)
  Downgraded: K
  Upgraded: L
  Unchanged: M

DEBATE-1: [title]
  Theorist: [SEVERITY] -> Practitioner: [SEVERITY] ([reason])
  ...
```

**3.5 PAUSE CONDITION**

If severity disagreement between theorists and practitioners exceeds 50% (e.g., theorist says CRITICAL, practitioner says LOW):

Show both positions to user with evidence and confidence:
```
-- Pause: expert disagreement --
DEBATE-N: [title]

  [Theorist role] ([SEVERITY]):
    "[argument quote]"
    Evidence: `file:line`
    Confidence: [level] ([reason])

  [Practitioner role] ([SEVERITY]):
    "[counter-argument quote]"
    Evidence: `file:line`
    Confidence: [level] ([reason])

  Disagreement: [OLD] vs [NEW] (>50%)

  Your verdict?
  [A] [Recommended option with reasoning]
  [B] [Alternative]
  [C] Your own decision
```

### ROUND 4: Cross-Examination

For each remaining CONTESTED decision:

**4.1 Theorists DEFEND**:
- Respond to each practitioner counter-argument
- May present NEW evidence from code (use Read, Grep)
- May strengthen argument with Context7 documentation

**4.2 Practitioners ATTACK**:
- Counter-examples from codebase (working analogous pattern)
- Cost comparison: fix cost vs bug cost
- May **dismiss** if theorist cannot provide `file:line` evidence

**4.3 Burden of proof rule**:
If a theorist cannot point to a specific `file:line` where the problem manifests, the issue is DISMISSED by the judge. This is non-negotiable.

**4.4 Output progress**
```
=== ROUND 4/5: Cross-Examination ===
DEBATE-1: [Theorist defended / Practitioner won / New evidence found]
DEBATE-2: ...
```

### ROUND 5: Judge — Algorithmic Verdict

**5.1 Separate RUNTIME_BLOCKERs**

Scan all findings for issues where the application literally won't start or will crash on the most basic interaction. These are NOT debated:
```
Known Blockers (not debated):
  KB-1: [description] — file: [file:line] — obvious fix
```

**5.2 Categorize each CONTESTED decision**

| Category | Definition | Priority Implication |
|----------|-----------|---------------------|
| SILENT_BOMB | Works during testing, breaks later (hours/days/weeks) | MAXIMUM — hardest to detect |
| LOUD_FAILURE | Breaks immediately, QA will catch on first test | MEDIUM — will be found before prod |
| COSMETIC | UX friction, not data corruption or crash | LOW — polish, not critical |

**5.3 Score each decision**

For each DEBATE-N, assign scores with EXPLICIT justification:

```
Effective_Priority =
  (Impact[1-5] × Probability[1-5] × Blast_Radius[1-5])
  / (QA_Detectability[1-5] × Reversibility[1-5])
  + Arch_Debt_Bonus[0-3]
```

**Parameter definitions** (judge MUST explain each score):

| Parameter | 1 | 2 | 3 | 4 | 5 |
|-----------|---|---|---|---|---|
| Impact | Cosmetic | UX friction | Wrong data displayed | Data loss/corruption | Crash or security breach |
| Probability | Theoretical only | Yearly | Monthly | Weekly | Every use |
| Blast_Radius | One component | One module | Cross-module | Cross-feature | System-wide |
| QA_Detectability | Invisible (time-delayed, race condition) | Delayed (hours+) | Specific scenario | Uncommon path | Basic smoke test |
| Reversibility | Requires data migration | Breaking API change | Schema migration | Code refactor | Config/code change |

| Arch_Debt | 0 | 1 | 2 | 3 |
|-----------|---|---|---|---|
| | No debt | Minor (annoyance) | Blocks future feature | Systemic debt across modules |

**Priority thresholds**:
- ≥5.0 → CRITICAL (fix before release)
- 3.0–4.9 → HIGH (fix in current sprint)
- 1.5–2.9 → MEDIUM (next sprint)
- <1.5 → LOW (backlog)

**5.4 Assess Confidence**

For each verdict, evaluate confidence on 3 axes:

| Axis | Question | LOW | MEDIUM | HIGH |
|------|----------|-----|--------|------|
| Information Sufficiency | Enough data to confirm/refute? | Missing key files/docs | Some gaps | Full picture |
| Context Sufficiency | Business context, project stage clear? | Unknown stage/constraints | Partially clear | Fully understood |
| Refutation Status | Was there an unresolved counter-argument? | STRONG (not dismissed in R4) | WEAK (dismissed but valid point) | NONE (unanimous) |

```
Final Confidence = min(Information, Context)
  if Refutation = STRONG → downgrade by 1 level
```

**Actions by confidence**:
- **HIGH**: Verdict is reliable. Execute.
- **MEDIUM**: Verdict is probable. Execute with [REVIEW] marker.
- **LOW**: Insufficient data. PAUSE — ask user for additional context before finalizing.

**5.5 Render verdict for each DEBATE-N**

```
### Judge's Verdict

**Decision**: ACCEPT | CHANGE | DEFER
**Priority Score**: X.X
**Category**: SILENT_BOMB | LOUD_FAILURE | COSMETIC

**Scores**:
| Parameter | Value | Justification |
|-----------|-------|---------------|
| Impact | N | [specific reason] |
| Probability | N | [specific reason] |
| Blast_Radius | N | [specific reason] |
| QA_Detectability | N | [specific reason] |
| Reversibility | N | [specific reason] |
| Arch_Debt | N | [specific reason] |

**Confidence**:
| Axis | Level | Justification |
|------|-------|---------------|
| Information | [level] | [reason] |
| Context | [level] | [reason] |
| Refutation | [level] | [reason] |
| **Final** | **[level]** | |

**Justification**: [2-3 sentences with references to expert arguments]
```

**5.6 Summary Matrix**

```
=== JUDGE'S VERDICT ===

| # | Decision | Verdict | Priority | Confidence | Category |
|---|----------|---------|----------|------------|----------|
| 1 | ... | CHANGE | X.X HIGH | HIGH | SILENT_BOMB |
| 2 | ... | ACCEPT | — | HIGH | — |
...

Known Blockers: [count]
Recommended order: #N -> #M -> #K
Justification: [why this order]
```

**5.7 Save to Memory**

For each DEBATE-N with verdict CHANGE or ACCEPT:
```
mcp_memory.create_entities([{
  name: "debate-pattern:{topic-slug}",
  entityType: "debate-pattern",
  observations: [
    "verdict: {ACCEPT|CHANGE|DEFER}",
    "priority: {score}",
    "category: {category}",
    "confidence: {level}",
    "reasoning: {1-line summary}",
    "feature: {branch}",
    "date: {ISO date}"
  ]
}])
```

### 6. Write Output

Load `.specify/templates/debates-template.md` and fill all sections.

**Output path**:
- single/cross mode: `FEATURE_DIR/debates.md`
- per-feature mode: `{target_feature_dir}/debates-{NNN}.md`

### 7. Final Report

```
=== Expert Debates Complete ===
Mode: [single|per-feature|cross]
Decisions analyzed: N
  CONTESTED → debated: M
  UNANIMOUS → confirmed: K
  RUNTIME_BLOCKER → known blockers: J

Verdicts:
  CHANGE: X (spec needs update)
  ACCEPT: Y (spec is correct)
  DEFER: Z (backlog)

Confidence: H high, M medium, L low
  [REVIEW] items: N (need additional context)

Written to: {path}
Next: /speckit.evaluate
```

## Debate Rules (NON-NEGOTIABLE)

1. **Burden of proof on theorist**: No `file:line` → argument not counted by judge
2. **Practitioner can dismiss**: With justification (QA catches it / edge case <0.1% / no real users)
3. **RUNTIME_BLOCKER not debated**: Obvious problems go to Known Blockers section, user notified
4. **Architectural reliability > speed**: When all else equal, prefer the more reliable solution
5. **SILENT_BOMB > LOUD_FAILURE**: Problems hardest to detect at runtime get higher priority
6. **User is the ultimate arbiter**: At pause points, user's decision overrides any expert

## Context

$ARGUMENTS
