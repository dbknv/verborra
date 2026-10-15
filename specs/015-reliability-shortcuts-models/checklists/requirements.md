# Specification Quality Checklist: Reliability, Shortcuts & Model List Update

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-10-14
**Feature**: [spec.md](../spec.md)

## Content Quality

- [X] No implementation details (languages, frameworks, APIs)
- [X] Focused on user value and business needs
- [X] Written for non-technical stakeholders
- [X] All mandatory sections completed

## Requirement Completeness

- [X] No [NEEDS CLARIFICATION] markers remain
- [X] Requirements are testable and unambiguous
- [X] Success criteria are measurable
- [X] Success criteria are technology-agnostic (no implementation details)
- [X] All acceptance scenarios are defined
- [X] Edge cases are identified
- [X] Scope is clearly bounded
- [X] Dependencies and assumptions identified

## Feature Readiness

- [X] All functional requirements have clear acceptance criteria
- [X] User scenarios cover primary flows
- [X] Feature meets measurable outcomes defined in Success Criteria
- [X] No implementation details leak into specification

## Notes

- Technical root-cause evidence (code references, log timelines, crash reports) is intentionally kept in `investigation.md`, not in the spec.
- FR-006 (stable signing identity) is a distribution requirement, kept because it is a confirmed contributor to the login bug; implementation choice is deferred to planning.
- Clarifications are recorded in the spec's Clarifications section (session 2026-10-14: retry behaviour, onboarding login prompt, per-session prompt choice, Fn glyph, hotkey during start, Bluetooth switch timing, the model-list decisions, and one release for all eight stories). Remaining defaults are in Assumptions.

**Model list (US5–US8, merged from former spec 016):**

- 2026-10-14 rewrite: spec replaced with the updated model list (GPT-5.6 Terra/Sol, GPT-6 Luna/Sol/Astra, GPT-6.1 Sol, GPT Transcribe; new defaults for new installs). Scope decisions recorded in the spec's Clarifications section; no [NEEDS CLARIFICATION] markers.
- Model names and prices are user-facing product facts, not implementation details. Context sizes, endpoint compatibility and accepted request settings are deferred to planning (see Assumptions).
- Prices and shutdown dates come from the user's description and are not independently verified here; planning must confirm them against OpenAI's documentation.
- FR-037: any saved or inherited selection that isn't in the new lists (including the old defaults) moves to the new default at launch, silently, with a log entry. Handled by the launch migrator (plan R24, tasks T029–T032).
