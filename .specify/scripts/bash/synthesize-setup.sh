#!/usr/bin/env bash

# Setup for synthesize command - validates sources and prepares feature environment
#
# This script validates parsed sources, creates the feature branch/directory,
# and returns paths for LLM consumption.
#
# Usage: ./synthesize-setup.sh [OPTIONS]
#
# OPTIONS:
#   --json                  Output JSON format (default)
#   --feature-name NAME     Short name for feature branch (required unless --dry-run)
#   --sources-json JSON     Parsed sources JSON from parse-sources.sh
#   --sources-file FILE     Path to file containing parsed sources JSON
#   --dry-run               Don't create git branch or directories
#   --skip-branch           Don't create git branch (but create directories)
#   --description DESC      Feature description for spec.md
#   --checkpoint FILE       Path to checkpoint file (for resume)
#   --save-checkpoint       Save checkpoint after setup
#   --help, -h              Show help message
#
# OUTPUT (JSON):
# {
#   "success": true,
#   "BRANCH_NAME": "007-user-auth",
#   "FEATURE_DIR": "/path/to/specs/007-user-auth",
#   "SPEC_FILE": "/path/to/specs/007-user-auth/spec.md",
#   "CHECKLIST_DIR": "/path/to/specs/007-user-auth/checklists",
#   "sources_validated": 5,
#   "created": true,
#   "warnings": [],
#   "errors": []
# }

set -e

# Source common functions
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Defaults
JSON_MODE=true
FEATURE_NAME=""
SOURCES_JSON=""
SOURCES_FILE=""
DRY_RUN=false
SKIP_BRANCH=false
DESCRIPTION="Synthesized specification"
CHECKPOINT_FILE=""
SAVE_CHECKPOINT=false
DEGRADED_MODE=false

# Arrays for results
declare -a WARNINGS=()
declare -a ERRORS=()

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --json)
            JSON_MODE=true
            shift
            ;;
        --feature-name)
            FEATURE_NAME="$2"
            shift 2
            ;;
        --sources-json)
            SOURCES_JSON="$2"
            shift 2
            ;;
        --sources-file)
            SOURCES_FILE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-branch)
            SKIP_BRANCH=true
            shift
            ;;
        --description)
            DESCRIPTION="$2"
            shift 2
            ;;
        --checkpoint)
            CHECKPOINT_FILE="$2"
            shift 2
            ;;
        --save-checkpoint)
            SAVE_CHECKPOINT=true
            shift
            ;;
        --help|-h)
            cat << 'EOF'
Usage: synthesize-setup.sh [OPTIONS]

Setup for synthesize command - validates sources and prepares feature environment.

OPTIONS:
  --json                  Output JSON format (default)
  --feature-name NAME     Short name for feature branch (required unless --dry-run)
  --sources-json JSON     Parsed sources JSON from parse-sources.sh
  --sources-file FILE     Path to file containing parsed sources JSON
  --dry-run               Don't create git branch or directories
  --skip-branch           Don't create git branch (but create directories)
  --description DESC      Feature description for spec.md
  --checkpoint FILE       Resume from checkpoint file
  --save-checkpoint       Save checkpoint after successful setup
  --help, -h              Show this help

EXAMPLES:
  # Normal setup with sources validation
  ./synthesize-setup.sh --feature-name "user-auth" --sources-file /tmp/sources.json

  # Dry run (validation only)
  ./synthesize-setup.sh --dry-run --sources-json '{"sources":[...]}'

  # Setup with description
  ./synthesize-setup.sh --feature-name "api-docs" --description "Synthesize API documentation"

EOF
            exit 0
            ;;
        *)
            ERRORS+=("Unknown option: $1")
            shift
            ;;
    esac
done

# Load sources JSON from file if provided
if [[ -n "$SOURCES_FILE" ]] && [[ -f "$SOURCES_FILE" ]]; then
    SOURCES_JSON=$(cat "$SOURCES_FILE")
fi

# Load checkpoint if provided (for resume)
RESUMED_FROM_CHECKPOINT=false
if [[ -n "$CHECKPOINT_FILE" ]] && [[ -f "$CHECKPOINT_FILE" ]]; then
    # Parse checkpoint to extract previous state (handles "key": value with spaces)
    checkpoint_phase=$(grep -oE '"phase":[[:space:]]*[0-9]+' "$CHECKPOINT_FILE" | grep -oE '[0-9]+' || echo "0")
    checkpoint_branch=$(grep -oE '"branch_name":[[:space:]]*"[^"]+"' "$CHECKPOINT_FILE" | sed 's/.*"\([^"]*\)"$/\1/' || echo "")
    checkpoint_dir=$(grep -oE '"feature_dir":[[:space:]]*"[^"]+"' "$CHECKPOINT_FILE" | sed 's/.*"\([^"]*\)"$/\1/' || echo "")
    
    if [[ $checkpoint_phase -ge 3 ]] && [[ -n "$checkpoint_branch" ]]; then
        WARNINGS+=("Resuming from checkpoint (phase $checkpoint_phase): $checkpoint_branch")
        RESUMED_FROM_CHECKPOINT=true
        # Use checkpoint values if feature name not explicitly provided
        if [[ -z "$FEATURE_NAME" ]]; then
            FEATURE_NAME=$(echo "$checkpoint_branch" | sed 's/^[0-9]*-//')
        fi
    fi
fi

# Validate inputs
if [[ -z "$FEATURE_NAME" ]] && [[ "$DRY_RUN" != "true" ]] && [[ "$RESUMED_FROM_CHECKPOINT" != "true" ]]; then
    ERRORS+=("--feature-name is required unless --dry-run is specified")
fi

# Get repository root
REPO_ROOT=$(get_repo_root)
SPECS_DIR="$REPO_ROOT/specs"

# Validate sources if provided
sources_count=0
sources_valid=0
total_size_kb=0

if [[ -n "$SOURCES_JSON" ]]; then
    # Parse sources JSON to validate
    sources_success=$(echo "$SOURCES_JSON" | grep -o '"success":[^,}]*' | cut -d':' -f2 | tr -d ' ')

    if [[ "$sources_success" == "false" ]]; then
        # Extract errors from sources JSON
        sources_errors=$(echo "$SOURCES_JSON" | grep -o '"errors":\[[^]]*\]' | sed 's/"errors":\[//;s/\]$//')
        ERRORS+=("Source parsing failed: $sources_errors")
    fi

    # Extract stats
    sources_count=$(echo "$SOURCES_JSON" | grep -o '"total_files":[0-9]*' | cut -d':' -f2 || echo "0")
    total_size_kb=$(echo "$SOURCES_JSON" | grep -o '"total_size_kb":[0-9]*' | cut -d':' -f2 || echo "0")

    # Count existing sources
    sources_valid=$sources_count

    # Check for warnings about missing files
    if echo "$SOURCES_JSON" | grep -q '"exists":false'; then
        missing_count=$(echo "$SOURCES_JSON" | grep -o '"exists":false' | wc -l)
        WARNINGS+=("$missing_count source file(s) not found")
        sources_valid=$((sources_count - missing_count))
    fi
fi

# Graceful Degradation: partial missing sources = warning, not error
# Only error if ALL sources are missing
if [[ -n "$SOURCES_JSON" ]]; then
    if [[ $sources_valid -eq 0 ]]; then
        ERRORS+=("No valid source files found")
    elif [[ $sources_valid -lt $sources_count ]]; then
        missing=$((sources_count - sources_valid))
        WARNINGS+=("Graceful degradation: ${missing}/${sources_count} sources unavailable, continuing with ${sources_valid} available")
        DEGRADED_MODE=true
    fi
fi

# Function to get highest feature number
get_highest_feature_number() {
    local highest=0

    # Check specs directory
    if [[ -d "$SPECS_DIR" ]]; then
        for dir in "$SPECS_DIR"/*; do
            [[ -d "$dir" ]] || continue
            dirname=$(basename "$dir")
            if [[ "$dirname" =~ ^([0-9]+)- ]]; then
                number=$((10#${BASH_REMATCH[1]}))
                if [[ $number -gt $highest ]]; then
                    highest=$number
                fi
            fi
        done
    fi

    # Check git branches if available
    if has_git; then
        while IFS= read -r branch; do
            clean_branch=$(echo "$branch" | sed 's/^[* ]*//; s|^remotes/[^/]*/||')
            if [[ "$clean_branch" =~ ^([0-9]+)- ]]; then
                number=$((10#${BASH_REMATCH[1]}))
                if [[ $number -gt $highest ]]; then
                    highest=$number
                fi
            fi
        done < <(git branch -a 2>/dev/null || true)
    fi

    echo $highest
}

# Calculate next feature number
HIGHEST=$(get_highest_feature_number)
NEXT_NUMBER=$((HIGHEST + 1))
PADDED_NUMBER=$(printf "%03d" $NEXT_NUMBER)

# Format feature name (lowercase, hyphens)
CLEAN_FEATURE_NAME=$(echo "$FEATURE_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[^a-z0-9-]//g')

# Build branch and paths
BRANCH_NAME="${PADDED_NUMBER}-${CLEAN_FEATURE_NAME}"
FEATURE_DIR="$SPECS_DIR/$BRANCH_NAME"
SPEC_FILE="$FEATURE_DIR/spec.md"
CHECKLIST_DIR="$FEATURE_DIR/checklists"
CONTRACTS_DIR="$FEATURE_DIR/contracts"
VERIFICATION_DIR="$FEATURE_DIR/verification"

# Check if feature already exists
if [[ -d "$FEATURE_DIR" ]]; then
    WARNINGS+=("Feature directory already exists: $FEATURE_DIR")
fi

created=false

# Create directories and branch unless dry-run
if [[ "$DRY_RUN" != "true" ]] && [[ ${#ERRORS[@]} -eq 0 ]]; then
    # Create specs directory if needed
    mkdir -p "$SPECS_DIR"

    # Create feature directory structure
    mkdir -p "$FEATURE_DIR"
    mkdir -p "$CHECKLIST_DIR"
    mkdir -p "$CONTRACTS_DIR"
    mkdir -p "$VERIFICATION_DIR"

    # Create git branch unless skip-branch
    if [[ "$SKIP_BRANCH" != "true" ]] && has_git; then
        current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")

        # Check if branch already exists
        if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME" 2>/dev/null; then
            WARNINGS+=("Git branch '$BRANCH_NAME' already exists, checking out")
            git checkout "$BRANCH_NAME" 2>/dev/null || true
        else
            # Create and checkout new branch
            git checkout -b "$BRANCH_NAME" 2>/dev/null || {
                WARNINGS+=("Could not create git branch, continuing without branch")
            }
        fi
    fi

    # Initialize empty spec.md if it doesn't exist
    if [[ ! -f "$SPEC_FILE" ]]; then
        cat > "$SPEC_FILE" << EOF
# Feature Specification: ${FEATURE_NAME}

**Feature Branch**: \`${BRANCH_NAME}\`
**Created**: $(date +%Y-%m-%d)
**Status**: Draft
**Method**: Synthesized from ${sources_count} source(s)

## Synthesis Metadata

**Generated**: $(date -Iseconds)
**Sources**: ${sources_count} files
**Total Size**: ${total_size_kb}KB

<!-- This spec will be populated by /speckit.synthesize -->

EOF
    fi

    created=true
fi

# Build JSON output
success="true"
if [[ ${#ERRORS[@]} -gt 0 ]]; then
    success="false"
fi

# Warnings array
warnings_json="["
first=true
for w in "${WARNINGS[@]}"; do
    if [[ "$first" != "true" ]]; then
        warnings_json+=","
    fi
    escaped_w="${w//\"/\\\"}"
    warnings_json+="\"$escaped_w\""
    first=false
done
warnings_json+="]"

# Errors array
errors_json="["
first=true
for e in "${ERRORS[@]}"; do
    if [[ "$first" != "true" ]]; then
        errors_json+=","
    fi
    escaped_e="${e//\"/\\\"}"
    errors_json+="\"$escaped_e\""
    first=false
done
errors_json+="]"

# Output JSON
cat << EOF
{
  "success": $success,
  "BRANCH_NAME": "$BRANCH_NAME",
  "FEATURE_NUMBER": $NEXT_NUMBER,
  "FEATURE_DIR": "$FEATURE_DIR",
  "SPEC_FILE": "$SPEC_FILE",
  "CHECKLIST_DIR": "$CHECKLIST_DIR",
  "CONTRACTS_DIR": "$CONTRACTS_DIR",
  "VERIFICATION_DIR": "$VERIFICATION_DIR",
  "REPO_ROOT": "$REPO_ROOT",
  "sources_validated": $sources_valid,
  "sources_total": $sources_count,
  "total_size_kb": $total_size_kb,
  "created": $created,
  "dry_run": $DRY_RUN,
  "degraded_mode": $DEGRADED_MODE,
  "warnings": $warnings_json,
  "errors": $errors_json
}
EOF

# Save checkpoint if requested, successful, and not dry-run
if [[ "$SAVE_CHECKPOINT" == "true" ]] && [[ "$success" == "true" ]] && [[ "$DRY_RUN" != "true" ]] && [[ -n "$FEATURE_DIR" ]]; then
    CHECKPOINT_PATH="$FEATURE_DIR/.synthesize-state.json"
    cat > "$CHECKPOINT_PATH" << CHECKPOINT
{
  "phase": 3,
  "timestamp": "$(date -Iseconds)",
  "branch_name": "$BRANCH_NAME",
  "feature_dir": "$FEATURE_DIR",
  "sources_validated": $sources_valid,
  "sources_total": $sources_count,
  "degraded_mode": $DEGRADED_MODE,
  "completed_phases": ["parse", "score", "setup"]
}
CHECKPOINT
fi

# Exit with error if any errors
if [[ ${#ERRORS[@]} -gt 0 ]]; then
    exit 1
fi
