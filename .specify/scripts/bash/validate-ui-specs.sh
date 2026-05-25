#!/usr/bin/env bash
# Validate UI component specifications for completeness and correctness
# Usage: ./validate-ui-specs.sh --ui-dir <path> [--strict] [--json]

set -euo pipefail

# Source common functions
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# --- Configuration ---
UI_DIR=""
STRICT=false
JSON_OUTPUT=false

# Required sections for full template (molecules/organisms)
FULL_REQUIRED_SECTIONS=(
    "## Props Interface"
    "## States"
    "## Behavior"
    "## Accessibility"
    "## Dependencies"
)

# Required sections for simple template (atoms)
SIMPLE_REQUIRED_SECTIONS=(
    "## Props"
    "## States"
    "## Accessibility"
)

# --- Functions ---

print_usage() {
    cat <<EOF
Usage: $(basename "$0") --ui-dir <path> [--strict] [--json]

Validate UI component specifications for completeness and correctness.

Options:
  --ui-dir <path>   Path to ui/ directory containing component specs (required)
  --strict          Fail if any [TODO] markers remain (blocks /implement)
  --json            Output results as JSON instead of human-readable text

Examples:
  $(basename "$0") --ui-dir specs/001-feature/ui
  $(basename "$0") --ui-dir specs/001-feature/ui --strict
  $(basename "$0") --ui-dir specs/001-feature/ui --json
EOF
}

# Determine if component uses simple or full template
is_simple_template() {
    local file="$1"
    grep -q "^\*\*Type\*\*: Atom" "$file" 2>/dev/null
}

# Count [TODO] markers in a file
count_todos() {
    local file="$1"
    local count
    count=$(grep -o "\[TODO\]" "$file" 2>/dev/null | wc -l | tr -d ' ')
    echo "${count:-0}"
}

# Count [NEEDS JUSTIFICATION] markers
count_needs_justification() {
    local file="$1"
    local count
    count=$(grep -o "\[NEEDS JUSTIFICATION" "$file" 2>/dev/null | wc -l | tr -d ' ')
    echo "${count:-0}"
}

# Count [VISUAL_TODO] markers
count_visual_todos() {
    local file="$1"
    local count
    count=$(grep -o "\[VISUAL_TODO\]" "$file" 2>/dev/null | wc -l | tr -d ' ')
    echo "${count:-0}"
}

# Count <!-- EXPERT_NOTE: --> comments
count_expert_notes() {
    local file="$1"
    local count
    count=$(grep -o "<!-- EXPERT_NOTE:" "$file" 2>/dev/null | wc -l | tr -d ' ')
    echo "${count:-0}"
}

# Count [MCP_UNAVAILABLE] markers
count_mcp_unavailable() {
    local file="$1"
    local count
    count=$(grep -o "\[MCP_UNAVAILABLE\]" "$file" 2>/dev/null | wc -l | tr -d ' ')
    echo "${count:-0}"
}

# Check if Props have types defined
check_props_have_types() {
    local file="$1"
    # Look for Props table rows without type (pattern: | `name` | | )
    if grep -E "^\| \`[^\`]+\` \| \|" "$file" >/dev/null 2>&1; then
        return 1  # Found props without types
    fi
    return 0
}

# Validate a single component spec
validate_component() {
    local file="$1"
    local filename=$(basename "$file")
    local issues=()
    local warnings=()
    local completeness=100

    # Skip index files
    if [[ "$filename" == "_index.md" ]]; then
        echo "SKIP|$filename|index_file"
        return
    fi

    # Check file is not empty
    if [[ ! -s "$file" ]]; then
        echo "FAIL|$filename|0|empty_file"
        return
    fi

    # Count [TODO] markers
    local todo_count=$(count_todos "$file")
    if [[ $todo_count -gt 0 ]]; then
        issues+=("$todo_count [TODO] markers remaining")
        completeness=$((completeness - todo_count * 5))
    fi

    # Count [NEEDS JUSTIFICATION] markers
    local justify_count
    justify_count=$(count_needs_justification "$file")
    if [[ $justify_count -gt 0 ]]; then
        warnings+=("$justify_count [NEEDS JUSTIFICATION] markers")
    fi

    # Count [VISUAL_TODO] markers
    local visual_todo_count
    visual_todo_count=$(count_visual_todos "$file")
    if [[ $visual_todo_count -gt 0 ]]; then
        warnings+=("$visual_todo_count [VISUAL_TODO] markers")
    fi

    # Count <!-- EXPERT_NOTE: --> comments (informational, not a warning)
    local expert_note_count
    expert_note_count=$(count_expert_notes "$file")

    # Count [MCP_UNAVAILABLE] markers
    local mcp_unavailable_count
    mcp_unavailable_count=$(count_mcp_unavailable "$file")
    if [[ $mcp_unavailable_count -gt 0 ]]; then
        warnings+=("$mcp_unavailable_count [MCP_UNAVAILABLE] markers")
    fi

    # Determine template type and required sections
    local sections=()
    local template_type="full"
    if is_simple_template "$file"; then
        sections=("${SIMPLE_REQUIRED_SECTIONS[@]}")
        template_type="simple"
    else
        sections=("${FULL_REQUIRED_SECTIONS[@]}")
    fi

    # Check required sections
    for section in "${sections[@]}"; do
        if ! grep -q "^$section" "$file" 2>/dev/null; then
            issues+=("Missing section: $section")
            completeness=$((completeness - 10))
        fi
    done

    # Check Props have types
    if ! check_props_have_types "$file"; then
        issues+=("Props without types defined")
        completeness=$((completeness - 10))
    fi

    # Check for Figma reference (warning only)
    if ! grep -q "\*\*Figma\*\*:" "$file" 2>/dev/null; then
        warnings+=("No Figma reference")
    elif grep -q '\*\*Figma\*\*: \[TODO\]' "$file" 2>/dev/null; then
        warnings+=("Figma URL is [TODO]")
    fi

    # Check for User Story reference
    if ! grep -q "\*\*User Story\*\*:" "$file" 2>/dev/null; then
        warnings+=("No User Story reference")
    fi

    # Ensure completeness doesn't go below 0
    [[ $completeness -lt 0 ]] && completeness=0

    # Determine validation result
    local status="PASS"
    local issues_str="${issues[*]:-none}"
    local warnings_str="${warnings[*]:-none}"

    if [[ ${#issues[@]} -gt 0 ]]; then
        status="FAIL"
    fi

    # In strict mode, any TODO markers cause failure
    if $STRICT && [[ $todo_count -gt 0 ]]; then
        status="FAIL"
    fi

    echo "$status|$filename|$template_type|$completeness|$todo_count|$justify_count|$visual_todo_count|$expert_note_count|$mcp_unavailable_count|$issues_str|$warnings_str"
}

# Output results as JSON
output_json() {
    local results=("$@")
    local valid_count=0
    local invalid_count=0
    local skip_count=0

    echo "{"
    echo "  \"strict_mode\": $STRICT,"
    echo "  \"ui_dir\": \"$UI_DIR\","
    echo "  \"components\": ["

    local first=true
    for result in "${results[@]}"; do
        IFS='|' read -r status filename template completeness todos justifications visual_todos expert_notes mcp_unavailable issues warnings <<< "$result"

        if [[ "$status" == "SKIP" ]]; then
            skip_count=$((skip_count + 1))
            continue
        fi

        [[ "$first" != "true" ]] && echo ","
        first=false

        local valid_bool="false"
        if [[ "$status" == "PASS" ]]; then
            valid_bool="true"
            valid_count=$((valid_count + 1))
        else
            invalid_count=$((invalid_count + 1))
        fi

        cat <<COMPONENT
    {
      "file": "$filename",
      "template": "$template",
      "valid": $valid_bool,
      "completeness": $completeness,
      "todo_count": $todos,
      "justification_count": $justifications,
      "visual_todo_count": $visual_todos,
      "expert_note_count": $expert_notes,
      "mcp_unavailable_count": $mcp_unavailable,
      "issues": "$issues",
      "warnings": "$warnings"
    }
COMPONENT
    done

    echo ""
    echo "  ],"
    echo "  \"summary\": {"
    echo "    \"total\": $((valid_count + invalid_count)),"
    echo "    \"valid\": $valid_count,"
    echo "    \"invalid\": $invalid_count,"
    echo "    \"skipped\": $skip_count,"
    echo "    \"all_valid\": $([[ $invalid_count -eq 0 ]] && echo "true" || echo "false")"
    echo "  }"
    echo "}"
}

# Output results as human-readable text
output_text() {
    local results=("$@")
    local valid_count=0
    local invalid_count=0
    local total_todos=0
    local total_visual_todos=0
    local total_expert_notes=0

    echo "═══════════════════════════════════════════════════════════════"
    echo "  UI Specs Validation Report"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "Directory: $UI_DIR"
    echo "Mode: $($STRICT && echo "STRICT (blocks on [TODO])" || echo "STANDARD")"
    echo ""
    echo "───────────────────────────────────────────────────────────────"

    for result in "${results[@]}"; do
        IFS='|' read -r status filename template completeness todos justifications visual_todos expert_notes mcp_unavailable issues warnings <<< "$result"

        if [[ "$status" == "SKIP" ]]; then
            continue
        fi

        total_todos=$((total_todos + todos))
        total_visual_todos=$((total_visual_todos + visual_todos))
        total_expert_notes=$((total_expert_notes + expert_notes))

        local icon="✓"
        if [[ "$status" == "FAIL" ]]; then
            icon="✗"
            invalid_count=$((invalid_count + 1))
        else
            valid_count=$((valid_count + 1))
        fi

        echo ""
        echo "$icon $filename [$template] — ${completeness}% complete"

        if [[ "$todos" -gt 0 ]]; then
            echo "  └─ [TODO] markers: $todos"
        fi

        if [[ "$visual_todos" -gt 0 ]]; then
            echo "  └─ [VISUAL_TODO] markers: $visual_todos"
        fi

        if [[ "$expert_notes" -gt 0 ]]; then
            echo "  └─ Expert notes preserved: $expert_notes"
        fi

        if [[ "$mcp_unavailable" -gt 0 ]]; then
            echo "  └─ [MCP_UNAVAILABLE] markers: $mcp_unavailable"
        fi

        if [[ "$justifications" -gt 0 ]]; then
            echo "  └─ [NEEDS JUSTIFICATION]: $justifications"
        fi

        if [[ "$issues" != "none" ]]; then
            echo "  └─ Issues: $issues"
        fi

        if [[ "$warnings" != "none" ]]; then
            echo "  └─ Warnings: $warnings"
        fi
    done

    echo ""
    echo "───────────────────────────────────────────────────────────────"
    echo ""
    echo "Summary:"
    echo "  Total components: $((valid_count + invalid_count))"
    echo "  Valid: $valid_count"
    echo "  Invalid: $invalid_count"
    echo "  Total [TODO] markers: $total_todos"
    echo "  Total [VISUAL_TODO] markers: $total_visual_todos"
    echo "  Total expert notes: $total_expert_notes"
    echo ""

    if [[ $invalid_count -gt 0 ]]; then
        echo "═══════════════════════════════════════════════════════════════"
        echo "  VALIDATION FAILED"
        echo "  $invalid_count component(s) need attention before /implement"
        echo "═══════════════════════════════════════════════════════════════"
        return 1
    else
        echo "═══════════════════════════════════════════════════════════════"
        echo "  VALIDATION PASSED"
        echo "  All UI specs are ready for /tasks and /implement"
        echo "═══════════════════════════════════════════════════════════════"
        return 0
    fi
}

# --- Main ---

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --ui-dir)
            UI_DIR="$2"
            shift 2
            ;;
        --strict)
            STRICT=true
            shift
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            echo "Error: Unknown option: $1" >&2
            print_usage >&2
            exit 1
            ;;
    esac
done

# Validate required arguments
if [[ -z "$UI_DIR" ]]; then
    echo "Error: --ui-dir is required" >&2
    print_usage >&2
    exit 1
fi

if [[ ! -d "$UI_DIR" ]]; then
    echo "Error: UI directory does not exist: $UI_DIR" >&2
    exit 1
fi

# Collect results
results=()

for file in "$UI_DIR"/*.md; do
    [[ ! -f "$file" ]] && continue
    result=$(validate_component "$file")
    results+=("$result")
done

# Check if any components found
if [[ ${#results[@]} -eq 0 ]]; then
    if $JSON_OUTPUT; then
        echo '{"error": "No UI component specs found", "ui_dir": "'"$UI_DIR"'"}'
    else
        echo "Error: No UI component specs (*.md) found in $UI_DIR" >&2
    fi
    exit 1
fi

# Output results
if $JSON_OUTPUT; then
    output_json "${results[@]}"
else
    output_text "${results[@]}"
fi
