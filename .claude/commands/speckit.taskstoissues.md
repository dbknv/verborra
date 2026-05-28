---
description: Convert existing tasks into actionable, dependency-ordered GitHub issues for the feature based on available design artifacts.
tools: ['github/github-mcp-server/issue_write']
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

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

1. Run `.specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks` from repo root and parse FEATURE_DIR and AVAILABLE_DOCS list. All paths must be absolute. For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").
1. From the executed script, extract the path to **tasks**.
1. Get the Git remote by running:

```bash
git config --get remote.origin.url
```

> [!CAUTION]
> ONLY PROCEED TO NEXT STEPS IF THE REMOTE IS A GITHUB URL

1. For each task in the list, use the GitHub MCP server to create a new issue in the repository that is representative of the Git remote.

> [!CAUTION]
> UNDER NO CIRCUMSTANCES EVER CREATE ISSUES IN REPOSITORIES THAT DO NOT MATCH THE REMOTE URL
