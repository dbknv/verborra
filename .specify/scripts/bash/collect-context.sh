#!/usr/bin/env bash
# Collect minimal context for LLM verification/fix operations.
#
# Usage: ./collect-context.sh --feature-dir <path> [OPTIONS]
#
# OPTIONS:
#   --feature-dir <path>   Path to feature directory
#   --task-id <id>         Task ID to collect context for
#   --issue <id>           Issue ID to collect context for
#   --level <L0-L4>        Verification level (default: L1)
#   --repo-root <path>     Repository root (auto-detected if not provided)
#   --help                 Show help message

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults
FEATURE_DIR=""
TASK_ID=""
ISSUE=""
LEVEL="L1"
REPO_ROOT=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --feature-dir)
            FEATURE_DIR="$2"
            shift 2
            ;;
        --task-id)
            TASK_ID="$2"
            shift 2
            ;;
        --issue)
            ISSUE="$2"
            shift 2
            ;;
        --level)
            LEVEL="$2"
            shift 2
            ;;
        --repo-root)
            REPO_ROOT="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $(basename "$0") --feature-dir <path> [OPTIONS]"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Validate
if [[ -z "$FEATURE_DIR" ]]; then
    echo '{"error": "Missing --feature-dir argument"}' >&2
    exit 1
fi

# Detect repo root
if [[ -z "$REPO_ROOT" ]]; then
    REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || realpath "$FEATURE_DIR/../..")
fi

# Context depth by level
get_config() {
    case "$1" in
        L0) echo '{"files": true, "signatures": false, "spec": false, "tests": false, "related": 0}' ;;
        L1) echo '{"files": true, "signatures": true, "spec": false, "tests": false, "related": 1}' ;;
        L2) echo '{"files": true, "signatures": true, "spec": true, "tests": true, "related": 2}' ;;
        L3) echo '{"files": true, "signatures": true, "spec": true, "tests": true, "related": 3}' ;;
        L4) echo '{"files": true, "signatures": true, "spec": true, "tests": true, "related": 5}' ;;
        *)  echo '{"files": true, "signatures": true, "spec": false, "tests": false, "related": 1}' ;;
    esac
}

CONFIG=$(get_config "$LEVEL")

# Find source of truth documents
find_sot() {
    local sources="[]"

    # spec.md
    if [[ -f "$FEATURE_DIR/spec.md" ]]; then
        sources=$(echo "$sources" | jq '. + [{"type": "spec", "file": "spec.md"}]')
    fi

    # data-model.md
    if [[ -f "$FEATURE_DIR/data-model.md" ]]; then
        sources=$(echo "$sources" | jq '. + [{"type": "data_model", "file": "data-model.md"}]')
    fi

    # contracts/
    if [[ -d "$FEATURE_DIR/contracts" ]]; then
        for yaml in "$FEATURE_DIR/contracts"/*.yaml "$FEATURE_DIR/contracts"/*.yml; do
            if [[ -f "$yaml" ]]; then
                local fname=$(basename "$yaml")
                sources=$(echo "$sources" | jq --arg f "contracts/$fname" '. + [{"type": "contract", "file": $f}]')
            fi
        done
    fi

    echo "$sources"
}

# Find implementation files based on task text
find_impl_files() {
    local task_text="$1"
    local files="[]"

    # Extract identifiers (CamelCase, snake_case)
    local identifiers=$(echo "$task_text" | grep -oE '[A-Z][a-z]+([A-Z][a-z]+)+|[a-z]+(_[a-z]+)+' | head -5)

    for id in $identifiers; do
        # Search for files
        local found=$(find "$REPO_ROOT" -type f \( -name "*${id}*" -o -name "*$(echo "$id" | tr '[:upper:]' '[:lower:]')*" \) \
            -not -path "*/node_modules/*" \
            -not -path "*/.git/*" \
            -not -path "*/dist/*" \
            -not -path "*/__pycache__/*" \
            \( -name "*.ts" -o -name "*.js" -o -name "*.py" -o -name "*.go" \) 2>/dev/null | head -5)

        for f in $found; do
            local rel_path="${f#$REPO_ROOT/}"
            files=$(echo "$files" | jq --arg p "$rel_path" --arg fp "$f" '. + [{"path": $p, "full_path": $fp, "type": "implementation"}]')
        done
    done

    echo "$files" | jq 'unique_by(.path)'
}

# Find test files for implementation files
find_test_files() {
    local impl_files="$1"
    local tests="[]"

    for impl in $(echo "$impl_files" | jq -r '.[].path'); do
        local base=$(basename "$impl" | sed 's/\.[^.]*$//')

        local found=$(find "$REPO_ROOT" -type f \
            \( -name "*test*${base}*" -o -name "*${base}*test*" -o -name "*${base}*.spec.*" \) \
            -not -path "*/node_modules/*" \
            -not -path "*/.git/*" 2>/dev/null | head -3)

        for f in $found; do
            local rel_path="${f#$REPO_ROOT/}"
            tests=$(echo "$tests" | jq --arg p "$rel_path" --arg fp "$f" --arg r "$impl" '. + [{"path": $p, "full_path": $fp, "related_to": $r}]')
        done
    done

    echo "$tests" | jq 'unique_by(.path)'
}

# Get task info if task ID provided
TASK_INFO="null"
if [[ -n "$TASK_ID" && -f "$SCRIPT_DIR/parse-tasks.sh" ]]; then
    TASK_INFO=$("$SCRIPT_DIR/parse-tasks.sh" --feature-dir "$FEATURE_DIR" --task-id "$TASK_ID" 2>/dev/null | jq '.tasks[0] // null')
fi

TASK_TEXT=""
if [[ "$TASK_INFO" != "null" ]]; then
    TASK_TEXT=$(echo "$TASK_INFO" | jq -r '.text // ""')
fi

# Collect context
SOT=$(find_sot)
IMPL_FILES=$(find_impl_files "$TASK_TEXT")
TEST_FILES="[]"

if [[ $(echo "$CONFIG" | jq '.tests') == "true" ]]; then
    TEST_FILES=$(find_test_files "$IMPL_FILES")
fi

# Contracts
CONTRACTS="[]"
if [[ $(echo "$CONFIG" | jq '.spec') == "true" && -d "$FEATURE_DIR/contracts" ]]; then
    for yaml in "$FEATURE_DIR/contracts"/*.yaml "$FEATURE_DIR/contracts"/*.yml; do
        if [[ -f "$yaml" ]]; then
            local fname=$(basename "$yaml")
            CONTRACTS=$(echo "$CONTRACTS" | jq --arg f "$fname" --arg p "$yaml" '. + [{"file": $f, "path": $p}]')
        fi
    done
fi

# Output
jq -n \
    --arg task_id "$TASK_ID" \
    --arg issue_id "$ISSUE" \
    --arg level "$LEVEL" \
    --arg feature_dir "$FEATURE_DIR" \
    --argjson task "$TASK_INFO" \
    --argjson source_of_truth "$SOT" \
    --argjson to_modify "$IMPL_FILES" \
    --argjson tests "$TEST_FILES" \
    --argjson contracts "$CONTRACTS" \
    '{
        task_id: (if $task_id == "" then null else $task_id end),
        issue_id: (if $issue_id == "" then null else $issue_id end),
        level: $level,
        feature_dir: $feature_dir,
        task: $task,
        source_of_truth: $source_of_truth,
        files: {
            to_modify: $to_modify,
            to_read: [],
            related: []
        },
        tests: $tests,
        contracts: $contracts
    }'
