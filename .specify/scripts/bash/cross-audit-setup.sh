#!/usr/bin/env bash

# Cross-audit setup script
#
# Resolves multiple feature directories and validates their spec.md files.
# Outputs a JSON payload for the cross-audit command.
#
# Usage: ./cross-audit-setup.sh [OPTIONS] <feature-numbers...>
#
# ARGUMENTS:
#   feature-numbers     Space-separated feature numbers (e.g., 005 007 008 009)
#                       Also accepts ranges: 005-009
#                       Also accepts '*' for all features
#
# OPTIONS:
#   --json              Output in JSON format (default: true)
#   --help, -h          Show help message
#
# OUTPUTS:
#   JSON mode:
#   {
#     "REPO_ROOT": "/path",
#     "CURRENT_BRANCH": "010-cross-feature-integrity",
#     "FEATURE_DIR": "/path/specs/010-...",
#     "AUDIT_TARGETS": [ { "number": "005", "dir": "...", ... } ],
#     "WARNINGS": [],
#     "ERRORS": []
#   }

set -e

# Parse command line arguments
JSON_MODE=true
FEATURE_NUMBERS=()

for arg in "$@"; do
    case "$arg" in
        --json)
            JSON_MODE=true
            ;;
        --help|-h)
            cat << 'EOF'
Usage: cross-audit-setup.sh [OPTIONS] <feature-numbers...>

Resolve multiple feature directories for cross-audit.

ARGUMENTS:
  feature-numbers     Space-separated: 005 007 008 009
                      Range: 005-009
                      All: *

OPTIONS:
  --json              Output in JSON format
  --help, -h          Show this help message

EXAMPLES:
  ./cross-audit-setup.sh --json 005 007 008 009
  ./cross-audit-setup.sh --json 005-009
  ./cross-audit-setup.sh --json '*'
EOF
            exit 0
            ;;
        *)
            FEATURE_NUMBERS+=("$arg")
            ;;
    esac
done

# Source common functions
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Get current feature paths
eval $(get_feature_paths)

WARNINGS=()
ERRORS=()

# Expand feature numbers
expand_feature_numbers() {
    local expanded=()
    local specs_dir="$REPO_ROOT/specs"

    for num in "${FEATURE_NUMBERS[@]}"; do
        if [[ "$num" == "*" ]]; then
            # All features
            for dir in "$specs_dir"/[0-9][0-9][0-9]-*; do
                if [[ -d "$dir" ]]; then
                    local dirname=$(basename "$dir")
                    if [[ "$dirname" =~ ^([0-9]{3})- ]]; then
                        expanded+=("${BASH_REMATCH[1]}")
                    fi
                fi
            done
        elif [[ "$num" =~ ^([0-9]{3})-([0-9]{3})$ ]]; then
            # Range: 005-009
            local start=$((10#${BASH_REMATCH[1]}))
            local end=$((10#${BASH_REMATCH[2]}))
            for ((i=start; i<=end; i++)); do
                expanded+=($(printf "%03d" $i))
            done
        elif [[ "$num" =~ ^[0-9]{3}$ ]]; then
            expanded+=("$num")
        else
            WARNINGS+=("Ignoring invalid feature number: $num")
        fi
    done

    # Deduplicate
    printf '%s\n' "${expanded[@]}" | sort -u
}

if [[ ${#FEATURE_NUMBERS[@]} -eq 0 ]]; then
    ERRORS+=("No feature numbers provided. Usage: cross-audit-setup.sh 005 007 008 009")
    if $JSON_MODE; then
        printf '{"REPO_ROOT":"%s","CURRENT_BRANCH":"%s","FEATURE_DIR":"%s","AUDIT_TARGETS":[],"WARNINGS":[],"ERRORS":["%s"]}\n' \
            "$REPO_ROOT" "$CURRENT_BRANCH" "$FEATURE_DIR" "${ERRORS[0]}"
    else
        echo "ERROR: ${ERRORS[0]}" >&2
    fi
    exit 1
fi

# Expand and resolve
EXPANDED=($(expand_feature_numbers))
TARGETS_JSON=""
TARGET_COUNT=0

for prefix in "${EXPANDED[@]}"; do
    # Find matching directory
    local_dir=""
    for dir in "$REPO_ROOT/specs/${prefix}"-*; do
        if [[ -d "$dir" ]]; then
            local_dir="$dir"
            break
        fi
    done

    if [[ -z "$local_dir" ]]; then
        WARNINGS+=("Feature $prefix: no spec directory found, skipping")
        continue
    fi

    dirname=$(basename "$local_dir")
    spec_file="$local_dir/spec.md"
    plan_file="$local_dir/plan.md"
    research_file="$local_dir/research.md"
    data_model_file="$local_dir/data-model.md"
    contracts_dir="$local_dir/contracts"

    has_spec="false"
    has_plan="false"
    has_research="false"
    has_data_model="false"
    has_contracts="false"

    [[ -f "$spec_file" ]] && has_spec="true"
    [[ -f "$plan_file" ]] && has_plan="true"
    [[ -f "$research_file" ]] && has_research="true"
    [[ -f "$data_model_file" ]] && has_data_model="true"
    [[ -d "$contracts_dir" && -n "$(ls -A "$contracts_dir" 2>/dev/null)" ]] && has_contracts="true"

    if [[ "$has_spec" != "true" ]]; then
        WARNINGS+=("Feature $prefix ($dirname): no spec.md found, skipping")
        continue
    fi

    if [[ -n "$TARGETS_JSON" ]]; then
        TARGETS_JSON="$TARGETS_JSON,"
    fi

    TARGETS_JSON="$TARGETS_JSON{\"number\":\"$prefix\",\"name\":\"$dirname\",\"dir\":\"$local_dir\",\"spec\":\"$spec_file\",\"plan\":\"$plan_file\",\"has_plan\":$has_plan,\"has_research\":$has_research,\"has_data_model\":$has_data_model,\"has_contracts\":$has_contracts}"
    TARGET_COUNT=$((TARGET_COUNT + 1))
done

# Build warnings JSON
WARNINGS_JSON=""
for w in "${WARNINGS[@]}"; do
    if [[ -n "$WARNINGS_JSON" ]]; then
        WARNINGS_JSON="$WARNINGS_JSON,"
    fi
    # Escape quotes in warning messages
    escaped_w=$(echo "$w" | sed 's/"/\\"/g')
    WARNINGS_JSON="$WARNINGS_JSON\"$escaped_w\""
done

ERRORS_JSON=""
for e in "${ERRORS[@]}"; do
    if [[ -n "$ERRORS_JSON" ]]; then
        ERRORS_JSON="$ERRORS_JSON,"
    fi
    escaped_e=$(echo "$e" | sed 's/"/\\"/g')
    ERRORS_JSON="$ERRORS_JSON\"$escaped_e\""
done

if $JSON_MODE; then
    printf '{"REPO_ROOT":"%s","CURRENT_BRANCH":"%s","FEATURE_DIR":"%s","TARGET_COUNT":%d,"AUDIT_TARGETS":[%s],"WARNINGS":[%s],"ERRORS":[%s]}\n' \
        "$REPO_ROOT" "$CURRENT_BRANCH" "$FEATURE_DIR" "$TARGET_COUNT" "$TARGETS_JSON" "$WARNINGS_JSON" "$ERRORS_JSON"
else
    echo "REPO_ROOT: $REPO_ROOT"
    echo "BRANCH: $CURRENT_BRANCH"
    echo "FEATURE_DIR: $FEATURE_DIR"
    echo "TARGETS ($TARGET_COUNT):"
    for prefix in "${EXPANDED[@]}"; do
        for dir in "$REPO_ROOT/specs/${prefix}"-*; do
            if [[ -d "$dir" && -f "$dir/spec.md" ]]; then
                echo "  ✓ $(basename "$dir")"
                check_file "$dir/plan.md" "plan.md"
                check_file "$dir/research.md" "research.md"
                check_file "$dir/data-model.md" "data-model.md"
            fi
        done
    done
    if [[ ${#WARNINGS[@]} -gt 0 ]]; then
        echo "WARNINGS:"
        for w in "${WARNINGS[@]}"; do
            echo "  ⚠ $w"
        done
    fi
fi
