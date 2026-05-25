# Verification Issues: [FEATURE_NAME]

**Feature**: [FEATURE_ID] — [FEATURE_NAME]
**Last Updated**: [TIMESTAMP]
**Total Issues**: [TOTAL_ISSUES]
**Open**: [OPEN_COUNT] | **Fixed**: [FIXED_COUNT] | **Blocked**: [BLOCKED_COUNT]

---

## Status Legend

| Badge | Status     | Description                    |
| ----- | ---------- | ------------------------------ |
| 🔴    | `detected` | Issue found, not yet addressed |
| 🟡    | `fixing`   | Fix in progress                |
| 🟢    | `fixed`    | Fix applied, pending recheck   |
| ✅    | `verified` | Fix verified successful        |
| ⛔    | `blocked`  | Needs human intervention       |
| ⏭️    | `wont_fix` | Intentionally not fixing       |

## Severity Legend

| Badge | Severity | Action                          |
| ----- | -------- | ------------------------------- |
| 🔴    | Critical | Fix immediately, blocks release |
| 🟠    | High     | Fix before merge                |
| 🟡    | Medium   | Fix when possible               |
| 🟢    | Low      | Nice to have                    |

---

## Open Issues

<!--
  Issues with status: detected, fixing, fixed (pending recheck)
  Sort: severity DESC, detected_at ASC
-->

### [ISSUE_ID]: [ISSUE_TITLE]

| Field                  | Value                                            |
| ---------------------- | ------------------------------------------------ |
| **Status**             | [STATUS_BADGE] `[STATUS]`                        |
| **Severity**           | [SEVERITY_BADGE] `[SEVERITY]`                    |
| **Type**               | `[ISSUE_TYPE]`                                   |
| **Task**               | [TASK_ID] — [TASK_DESCRIPTION]                   |
| **File**               | `[FILE_PATH]`                                    |
| **Detected**           | [DETECTED_AT]                                    |
| **Verification Level** | [VERIFICATION_LEVEL]                             |
| **Confidence**         | [CONFIDENCE]% (required: [CONFIDENCE_REQUIRED]%) |

**Description**:

> [ISSUE_DESCRIPTION]

**Source of Truth**:

- Type: `[SOT_TYPE]`
- Reference: [SOT_REFERENCE]
- Content: "[SOT_CONTENT]"

**Fix Context**:

- Auto-fixable: [CAN_AUTO_FIX]
- Suggested approach: [SUGGESTED_APPROACH]
- Affected files: [AFFECTED_FILES]
- Requires spec update: [REQUIRES_SPEC_UPDATE]

**Uncertainty**:

- Flags: [UNCERTAINTY_FLAGS]
- Reason: [CONFIDENCE_REASON]

<details>
<summary>Fix History ([FIX_ATTEMPTS] attempts)</summary>

| Attempt       | Date           | Approach   | Result   |
| ------------- | -------------- | ---------- | -------- |
| [ATTEMPT_NUM] | [ATTEMPT_DATE] | [APPROACH] | [RESULT] |

</details>

---

## Resolved Issues

<!--
  Issues with status: verified, wont_fix
  Collapsed by default
-->

<details>
<summary>✅ Resolved ([RESOLVED_COUNT] issues)</summary>

### [ISSUE_ID]: [ISSUE_TITLE]

| Field            | Value          |
| ---------------- | -------------- |
| **Status**       | ✅ `verified`  |
| **Type**         | `[ISSUE_TYPE]` |
| **Task**         | [TASK_ID]      |
| **Fixed**        | [FIXED_AT]     |
| **Fix Approach** | [FIX_APPROACH] |

</details>

---

## Blocked Issues

<!--
  Issues requiring human intervention
-->

<details>
<summary>⛔ Blocked ([BLOCKED_COUNT] issues)</summary>

### [ISSUE_ID]: [ISSUE_TITLE]

| Field                     | Value             |
| ------------------------- | ----------------- |
| **Status**                | ⛔ `blocked`      |
| **Blocking Reason**       | [BLOCKING_REASON] |
| **Human Action Required** | [HUMAN_ACTION]    |
| **Fix Attempts**          | [FIX_ATTEMPTS]    |

</details>

---

## Quick Actions

```bash
# Fix specific issue
/speckit.fix --issue [ISSUE_ID]

# Fix all open issues in batch
/speckit.fix --batch

# Re-verify after manual fix
/speckit.verify --recheck [ISSUE_ID]

# Mark as won't fix
# (manual edit: change status to wont_fix)
```

---

_Issues tracked by `/speckit.verify` and `/speckit.fix`. See [report.md](report.md) for summary._
