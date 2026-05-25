# Cross-Feature Audit: [FEATURES]

**Generated**: [TIMESTAMP]
**Scope**: [FEATURE_LIST]
**Branch**: [BRANCH]

---

## Dependency Graph

[Describe cross-feature dependencies as text or mermaid diagram]

```
Feature A ──FK──→ Feature B
Feature B ──FK──→ Feature C
Feature A ──shared service──→ Feature C
```

---

## Shared Entities

| Entity | Features | Role in Each | Potential Conflicts |
|--------|----------|--------------|---------------------|

---

## Findings

### [FINDING-ID] — [Title]

**Type**: CONFLICT | OVERLAP | DRIFT | DEPENDENCY
**Severity**: CRITICAL | HIGH | MEDIUM | LOW
**Features**: [NNN-name], [NNN-name]

**Evidence**:
```
file:line — exact code quote
file:line — exact code quote
```

**Description**: [What the finding means and why it matters]

**Impact**: [What breaks or degrades if not addressed]

---

## Summary

| Type | Count | Critical | High | Medium | Low |
|------|-------|----------|------|--------|-----|
| CONFLICT | | | | | |
| OVERLAP | | | | | |
| DRIFT | | | | | |
| DEPENDENCY | | | | | |
| **Total** | | | | | |

## Next Actions

- [ ] [Action item from findings]
