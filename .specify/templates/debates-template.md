# Expert Debates: [FEATURE]

**Generated**: [TIMESTAMP]
**Rounds**: 5
**Branch**: [BRANCH]
**Mode**: single | per-feature | cross

---

## Participants

| Role | Focus | Phase |
|------|-------|-------|
| Architect | System architecture, coupling, cohesion | Theorist (R2) |
| DBA | Data, migrations, constraints, query perf | Theorist (R2) |
| Security | Auth, data exposure, OWASP | Theorist (R2) |
| PRAGMA (Tech Lead) | Scope, effort/value, delivery speed | Practitioner (R3) |
| QA Mindset | Detectability, probability, regression risk | Practitioner (R3) |

---

## Known Blockers (not debated)

| # | Problem | File | Why obvious |
|---|---------|------|-------------|
| — | (none found) | — | — |

---

## DEBATE-[N]: [Title]

**Decision in spec**: [what is written in the current specification]
**Status**: CONTESTED → [VERDICT]

### Round 2: Theorists

**Architect**: [argument] (`file:line` — quote)

**DBA**: [argument] (`file:line` — quote)

**Security**: [argument] (`file:line` — quote)

### Round 3: Practitioners

**PRAGMA**: [calibration]
- Stage: MVP / prod / scale
- Effort: ~N LOC, M files
- 6-month impact: [what happens if deferred]

**QA Mindset**: [detectability assessment]
- QA test: [specific smoke test steps]
- Detectability: [found immediately / delayed / invisible]
- Probability: [daily / monthly / yearly / theoretical]
- User impact: [crash / wrong data / cosmetic / invisible]

### Round 4: Cross-examination

[Theorists defend → Practitioners attack]

### Judge's Verdict

**Decision**: ACCEPTED | MODIFY | DEFER
**Priority Score**: [X.X]
**Category**: RUNTIME_BLOCKER | SILENT_BOMB | LOUD_FAILURE | COSMETIC

**Scores**:
| Parameter | Value | Rationale |
|-----------|-------|-----------|
| Impact | [1-5] | [why] |
| Probability | [1-5] | [why] |
| Blast_Radius | [1-5] | [why] |
| QA_Detectability | [1-5] | [why] |
| Reversibility | [1-5] | [why] |
| Arch_Debt | [0-3] | [why] |

**Confidence**:
| Axis | Level | Rationale |
|------|-------|-----------|
| Information sufficiency | LOW / MEDIUM / HIGH | [are there gaps in the data] |
| Context sufficiency | LOW / MEDIUM / HIGH | [is the business context clear] |
| Presence of rebuttal | NONE / WEAK / STRONG | [was there an unaddressed argument] |
| **Final** | **[LOW / MEDIUM / HIGH]** | |

**Rationale**: [2-3 sentences with references to expert arguments]

---

## Summary Matrix

| # | Debate | Verdict | Category | Priority | Confidence | Effort |
|---|--------|---------|----------|----------|------------|--------|

## Recommended Implementation Order

### PR 1: [scope]
- [DEBATE-N]: [task]
- [DEBATE-M]: [task]
**Files**: [list]
**Reason**: [why first]

### PR 2: [scope]
...

## Next Actions

- [ ] [Action derived from verdicts]
