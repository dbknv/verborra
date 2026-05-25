#!/usr/bin/env bash
# Parse tasks.md into structured JSON for verification workflow.
# No external dependencies - pure bash.
#
# Usage: ./parse-tasks.sh --feature-dir <path> [OPTIONS]
#
# OPTIONS:
#   --feature-dir <path>   Path to feature directory containing tasks.md
#   --status <status>      Filter: completed, pending, all (default: all)
#   --story <id>           Filter by story ID (e.g., US1)
#   --task-id <id>         Get specific task by ID (e.g., T001)
#   --summary              Output summary statistics only
#   --json                 Output in JSON format (default)
#   --help                 Show help message

set -euo pipefail

# JSON escape function - pure bash
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

# Risk classification - optimized without subshells
get_risk_level() {
    local text="$1"
    local text_lower="${text,,}"
    case "$text_lower" in
        *auth*|*security*|*payment*|*billing*|*credential*|*token*|*session*|*permission*|*role*|*encrypt*)
            echo "critical"; return ;;
        *database*|*migration*|*api*|*contract*|*schema*|*validation*|*cache*|*queue*|*webhook*|*external*)
            echo "high"; return ;;
        *service*|*repository*|*handler*|*controller*|*middleware*|*transform*|*parse*|*serialize*|*format*)
            echo "medium"; return ;;
    esac
    echo "low"
}

get_verify_level() {
    case "$1" in
        critical) echo "L4" ;;
        high) echo "L2" ;;
        medium) echo "L1" ;;
        *) echo "L0" ;;
    esac
}

# Defaults
FEATURE_DIR=""
STATUS="all"
STORY=""
TASK_ID=""
SUMMARY=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --feature-dir) FEATURE_DIR="$2"; shift 2 ;;
        --status) STATUS="$2"; shift 2 ;;
        --story) STORY="$2"; shift 2 ;;
        --task-id) TASK_ID="$2"; shift 2 ;;
        --summary) SUMMARY=true; shift ;;
        --json) shift ;;
        --help|-h)
            echo "Usage: $(basename "$0") --feature-dir <path> [OPTIONS]"
            echo ""
            echo "OPTIONS:"
            echo "  --feature-dir <path>   Path to feature directory containing tasks.md"
            echo "  --status <status>      Filter: completed, pending, all (default: all)"
            echo "  --story <id>           Filter by story ID (e.g., US1)"
            echo "  --task-id <id>         Get specific task by ID"
            echo "  --summary              Output summary statistics only"
            echo "  --json                 Output in JSON format (default)"
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# Validate
if [[ -z "$FEATURE_DIR" ]]; then
    echo '{"error": "Missing --feature-dir argument"}' >&2
    exit 1
fi

TASKS_FILE="$FEATURE_DIR/tasks.md"
if [[ ! -f "$TASKS_FILE" ]]; then
    echo "{\"error\": \"tasks.md not found: $TASKS_FILE\"}" >&2
    exit 1
fi

# Initialize
declare -a ALL_TASKS=()
CURRENT_PHASE=""
CURRENT_STORY=""
CURRENT_CATEGORY=""
TASK_INDEX=0
TOTAL=0
COMPLETED=0
PENDING=0
VERIFIED=0
WITH_ISSUES=0
CRITICAL=0
HIGH=0
MEDIUM=0
LOW=0

# Main parsing loop
while IFS= read -r line || [[ -n "$line" ]]; do
    # Phase header: ## Phase 1: Setup
    if [[ "$line" =~ ^##[[:space:]]+Phase[[:space:]]+([0-9]+):[[:space:]]*(.+)$ ]]; then
        CURRENT_PHASE="Phase${BASH_REMATCH[1]}"
        CURRENT_STORY=""
        CURRENT_CATEGORY=""
        continue
    fi

    # Story header: ## US1: Story Name
    if [[ "$line" =~ ^##[[:space:]]+(US[0-9]+):[[:space:]]*(.+)$ ]]; then
        CURRENT_STORY="${BASH_REMATCH[1]}"
        CURRENT_CATEGORY=""
        continue
    fi

    # Alternative story header: User Story N
    if [[ "$line" =~ User[[:space:]]+Story[[:space:]]+([0-9]+) ]]; then
        CURRENT_STORY="US${BASH_REMATCH[1]}"
        continue
    fi

    # Category header: ### Category Name
    if [[ "$line" =~ ^###[[:space:]]+(.+)$ ]]; then
        CURRENT_CATEGORY="${BASH_REMATCH[1]}"
        continue
    fi

    # Task line: - [X] or - [ ]
    if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*\[([[:space:]Xx])\][[:space:]]*(.+)$ ]]; then
        CHECK_MARK="${BASH_REMATCH[1]}"
        TASK_TEXT="${BASH_REMATCH[2]}"
        TASK_INDEX=$((TASK_INDEX + 1))
        TOTAL=$((TOTAL + 1))

        # Check completion
        IS_COMPLETED=false
        if [[ "$CHECK_MARK" =~ [Xx] ]]; then
            IS_COMPLETED=true
            COMPLETED=$((COMPLETED + 1))
        else
            PENDING=$((PENDING + 1))
        fi

        # Extract markers
        ISSUE_ID=""
        IS_VERIFIED=false
        if [[ "$TASK_TEXT" =~ ISSUE:([A-Za-z0-9]+) ]]; then
            ISSUE_ID="${BASH_REMATCH[1]}"
            WITH_ISSUES=$((WITH_ISSUES + 1))
        fi
        if [[ "$TASK_TEXT" =~ VERIFIED ]]; then
            IS_VERIFIED=true
            VERIFIED=$((VERIFIED + 1))
        fi

        # Clean text - remove markers
        CLEAN_TEXT="$TASK_TEXT"
        CLEAN_TEXT="${CLEAN_TEXT//VERIFIED/}"
        CLEAN_TEXT="${CLEAN_TEXT//PENDING/}"
        [[ -n "$ISSUE_ID" ]] && CLEAN_TEXT="${CLEAN_TEXT//ISSUE:$ISSUE_ID/}"
        # Trim whitespace
        CLEAN_TEXT="${CLEAN_TEXT#"${CLEAN_TEXT%%[![:space:]]*}"}"
        CLEAN_TEXT="${CLEAN_TEXT%"${CLEAN_TEXT##*[![:space:]]}"}"

        # Extract task ID
        EXTRACTED_ID=""
        if [[ "$CLEAN_TEXT" =~ ^(T[0-9]+[a-z]?)[[:space:]] ]]; then
            EXTRACTED_ID="${BASH_REMATCH[1]}"
        fi
        FULL_TASK_ID="${EXTRACTED_ID:-T$TASK_INDEX}"

        # Risk classification
        RISK=$(get_risk_level "$CLEAN_TEXT")
        VERIFY_LEVEL=$(get_verify_level "$RISK")

        case "$RISK" in
            critical) CRITICAL=$((CRITICAL + 1)) ;;
            high) HIGH=$((HIGH + 1)) ;;
            medium) MEDIUM=$((MEDIUM + 1)) ;;
            low) LOW=$((LOW + 1)) ;;
        esac

        # Apply filters
        INCLUDE=true
        [[ "$STATUS" == "completed" && "$IS_COMPLETED" == "false" ]] && INCLUDE=false
        [[ "$STATUS" == "pending" && "$IS_COMPLETED" == "true" ]] && INCLUDE=false
        [[ -n "$STORY" && "$CURRENT_STORY" != "$STORY" ]] && INCLUDE=false
        [[ -n "$TASK_ID" && "$FULL_TASK_ID" != "$TASK_ID" ]] && INCLUDE=false

        if [[ "$INCLUDE" == "true" ]]; then
            ESCAPED_TEXT=$(json_escape "$CLEAN_TEXT")
            ESCAPED_PHASE=$(json_escape "$CURRENT_PHASE")
            ESCAPED_STORY=$(json_escape "$CURRENT_STORY")
            ESCAPED_CATEGORY=$(json_escape "$CURRENT_CATEGORY")

            ISSUE_JSON="null"
            [[ -n "$ISSUE_ID" ]] && ISSUE_JSON="\"$ISSUE_ID\""

            TASK_JSON="{\"id\":\"$FULL_TASK_ID\",\"phase\":\"$ESCAPED_PHASE\",\"story\":\"$ESCAPED_STORY\",\"category\":\"$ESCAPED_CATEGORY\",\"text\":\"$ESCAPED_TEXT\",\"completed\":$IS_COMPLETED,\"verified\":$IS_VERIFIED,\"issue_id\":$ISSUE_JSON,\"risk\":\"$RISK\",\"verify_level\":\"$VERIFY_LEVEL\"}"
            ALL_TASKS+=("$TASK_JSON")
        fi
    fi
done < "$TASKS_FILE"

# Build output JSON
ESCAPED_FEATURE_DIR=$(json_escape "$FEATURE_DIR")

if [[ "$SUMMARY" == "true" ]]; then
    echo "{\"feature_dir\":\"$ESCAPED_FEATURE_DIR\",\"stats\":{\"total\":$TOTAL,\"completed\":$COMPLETED,\"pending\":$PENDING,\"verified\":$VERIFIED,\"with_issues\":$WITH_ISSUES,\"by_risk\":{\"critical\":$CRITICAL,\"high\":$HIGH,\"medium\":$MEDIUM,\"low\":$LOW}}}"
else
    # Build tasks array
    if [[ ${#ALL_TASKS[@]} -eq 0 ]]; then
        TASKS_ARRAY="[]"
    else
        TASKS_ARRAY="["
        FIRST=true
        for task in "${ALL_TASKS[@]}"; do
            [[ "$FIRST" == "true" ]] && FIRST=false || TASKS_ARRAY+=","
            TASKS_ARRAY+="$task"
        done
        TASKS_ARRAY+="]"
    fi

    echo "{\"feature_dir\":\"$ESCAPED_FEATURE_DIR\",\"stats\":{\"total\":$TOTAL,\"completed\":$COMPLETED,\"pending\":$PENDING,\"verified\":$VERIFIED,\"with_issues\":$WITH_ISSUES,\"by_risk\":{\"critical\":$CRITICAL,\"high\":$HIGH,\"medium\":$MEDIUM,\"low\":$LOW}},\"tasks\":$TASKS_ARRAY}"
fi
