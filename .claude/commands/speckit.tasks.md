---
description: Generate an actionable, dependency-ordered tasks.md for the feature based on available design artifacts.
handoffs:
  - label: Analyze For Consistency
    agent: speckit.analyze
    prompt: Run a project analysis for consistency
    send: true
  - label: Implement Project
    agent: speckit.implement
    prompt: Start the implementation in phases
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

Use these English sources as inputs, but when generating the actual output documents, write them in Russian.

Target specs MUST be translates to Russian:

- Constitution (`.specify/memory/constitution.md`)
- Output specs (`specs/**`)

Do **NOT** translate product/service names, technology names, library/framework names, acronyms, or other proper technical terms—keep their original spelling (typically English).

## Outline

1. **Setup**: Run `.specify/scripts/bash/check-prerequisites.sh --json` from repo root and parse FEATURE_DIR and AVAILABLE_DOCS list. All paths must be absolute. For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").

2. **Load design documents**: Read from FEATURE_DIR:
   - **Required**: plan.md (tech stack, libraries, structure), spec.md (user stories with priorities)
   - **Optional**: data-model.md (entities), contracts/ (API endpoints), research.md (decisions), quickstart.md (test scenarios)
   - **Optional**: ui/\*.md (UI component specifications) — see step 2b
   - Note: Not all projects have all documents. Generate tasks based on what's available.

   **If ui/ directory does NOT exist** and spec.md contains UI-related User Stories:
   - **SUGGEST**: "UI specs not found. Run `/speckit.ui` with Figma URLs to create component specifications before generating tasks."
   - Continue without UI tasks if user chooses to proceed.

2b. **Load UI specifications** (if FEATURE_DIR/ui/ exists):

a. **Validate UI specs first**: - Run `.specify/scripts/bash/validate-ui-specs.sh --ui-dir FEATURE_DIR/ui --strict` - If validation fails (has [TODO] markers in strict mode): - **WARN**: "UI specs incomplete. Run human review first." - Ask user: "Generate tasks anyway? UI tasks will have [INCOMPLETE] marker. (yes/no)" - If "no", halt and suggest completing UI specs first

b. **Read all UI component specs** (excluding \_index.md): - For each `ui/*.md` file, extract: - **Component name** from `# UI Component: [NAME]` - **Type** (Atom/Molecule/Organism) from `**Type**:` - **User Story** reference from `**User Story**:` - **Dependencies** from Dependencies section

c. **Generate UI tasks for each component**:

````text
For each UI component from ui/\*.md:

      1. If Type = "Atom" (simple template):
         - [ ] TXXX [P] [USY] Create ComponentName in {path from plan.md}/ComponentName.tsx
         - [ ] TXXX [P] [USY] Add ComponentName tests in {path}/ComponentName.test.tsx

      2. If Type = "Molecule" or "Organism" (full template):
         - [ ] TXXX [P] [USY] Create ComponentName in {path}/ComponentName.tsx
         - [ ] TXXX [USY] Implement ComponentName states (list from States table)
         - [ ] TXXX [USY] Add ComponentName event handlers (from Behavior table)
         - [ ] TXXX [USY] Add ComponentName accessibility (from Accessibility section)
         - [ ] TXXX [P] [USY] Add ComponentName tests in {path}/ComponentName.test.tsx
      ```

d. **Group UI tasks by User Story** in the appropriate phase: - Match component's User Story reference to spec.md stories - Place tasks in that story's phase - If no User Story reference → place in "UI Components" sub-phase

e. **Generate [UI] styling tasks** for non-Atom components: - Run `.specify/scripts/bash/detect-ui-tasks.sh --ui-dir "$FEATURE_DIR/ui" --json` - For each returned component, create a styling task:
`- [ ] TXXX [P] [USY] [UI] Style {ComponentName} in {path/to/Component.tsx}` - [UI] tasks come AFTER the corresponding create task - [UI] tasks are parallelizable [P] if they don't share dependencies

3. **Execute task generation workflow**:
   - Load plan.md and extract tech stack, libraries, project structure
   - Load spec.md and extract user stories with their priorities (P1, P2, P3, etc.)
   - If data-model.md exists: Extract entities and map to user stories
   - If contracts/ exists: Map endpoints to user stories
   - If research.md exists: Extract decisions for setup tasks
   - If ui/\*.md exists: Generate UI component tasks (from step 2b)
   - Generate tasks organized by user story (see Task Generation Rules below)
   - Generate dependency graph showing user story completion order
   - Create parallel execution examples per user story
   - Validate task completeness (each user story has all needed tasks, independently testable)

4. **Generate tasks.md**: Use `.specify/templates/tasks-template.md` as structure, fill with:
   - Correct feature name from plan.md
   - Phase 1: Setup tasks (project initialization)
   - Phase 2: Foundational tasks (blocking prerequisites for all user stories)
   - Phase 3+: One phase per user story (in priority order from spec.md)
   - Each phase includes: story goal, independent test criteria, tests (if requested), implementation tasks
   - Final Phase: Polish & cross-cutting concerns
   - All tasks must follow the strict checklist format (see Task Generation Rules below)
   - Clear file paths for each task
   - Dependencies section showing story completion order
   - Parallel execution examples per story
   - Implementation strategy section (MVP first, incremental delivery)

5. **Report**: Output path to generated tasks.md and summary:
   - Total task count
   - Task count per user story
   - Parallel opportunities identified
   - Independent test criteria for each story
   - Suggested MVP scope (typically just User Story 1)
   - Format validation: Confirm ALL tasks follow the checklist format (checkbox, ID, labels, file paths)

Context for task generation: $ARGUMENTS

The tasks.md should be immediately executable - each task must be specific enough that an LLM can complete it without additional context.

## Task Generation Rules

**CRITICAL**: Tasks MUST be organized by user story to enable independent implementation and testing.

**Tests are OPTIONAL**: Only generate test tasks if explicitly requested in the feature specification or if user requests TDD approach.

### Checklist Format (REQUIRED)

Every task MUST strictly follow this format:

```text
- [ ] [TaskID] [P?] [Story?] Description with file path
````

**Format Components**:

1. **Checkbox**: ALWAYS start with `- [ ]` (markdown checkbox)
2. **Task ID**: Sequential number (T001, T002, T003...) in execution order
3. **[P] marker**: Include ONLY if task is parallelizable (different files, no dependencies on incomplete tasks)
4. **[UI] marker**: Include for styling tasks (component created, needs visual styling per Figma)
5. **[Story] label**: REQUIRED for user story phase tasks only
   - Format: [US1], [US2], [US3], etc. (maps to user stories from spec.md)
   - Setup phase: NO story label
   - Foundational phase: NO story label
   - User Story phases: MUST have story label
   - Polish phase: NO story label
6. **Description**: Clear action with exact file path

**Examples**:

- ✅ CORRECT: `- [ ] T001 Create project structure per implementation plan`
- ✅ CORRECT: `- [ ] T005 [P] Implement authentication middleware in src/middleware/auth.py`
- ✅ CORRECT: `- [ ] T012 [P] [US1] Create User model in src/models/user.py`
- ✅ CORRECT: `- [ ] T014 [US1] Implement UserService in src/services/user_service.py`
- ✅ CORRECT: `- [ ] T020 [P] [US1] [UI] Style LoginForm in src/components/auth/LoginForm.tsx`
- ❌ WRONG: `- [ ] Create User model` (missing ID and Story label)
- ❌ WRONG: `T001 [US1] Create model` (missing checkbox)
- ❌ WRONG: `- [ ] [US1] Create User model` (missing Task ID)
- ❌ WRONG: `- [ ] T001 [US1] Create model` (missing file path)

### Task Organization

1. **From User Stories (spec.md)** - PRIMARY ORGANIZATION:
   - Each user story (P1, P2, P3...) gets its own phase
   - Map all related components to their story:
     - Models needed for that story
     - Services needed for that story
     - Endpoints/UI needed for that story
     - If tests requested: Tests specific to that story
   - Mark story dependencies (most stories should be independent)

2. **From Contracts**:
   - Map each contract/endpoint → to the user story it serves
   - If tests requested: Each contract → contract test task [P] before implementation in that story's phase

3. **From Data Model**:
   - Map each entity to the user story(ies) that need it
   - If entity serves multiple stories: Put in earliest story or Setup phase
   - Relationships → service layer tasks in appropriate story phase

4. **From Setup/Infrastructure**:
   - Shared infrastructure → Setup phase (Phase 1)
   - Foundational/blocking tasks → Foundational phase (Phase 2)
   - Story-specific setup → within that story's phase

### Phase Structure

- **Phase 1**: Setup (project initialization)
- **Phase 2**: Foundational (blocking prerequisites - MUST complete before user stories)
- **Phase 3+**: User Stories in priority order (P1, P2, P3...)
  - Within each story: Tests (if requested) → Models → Services → Endpoints → Integration
  - Each phase should be a complete, independently testable increment
- **Final Phase**: Polish & Cross-Cutting Concerns
