#!/usr/bin/env bash

# Parse UI synthesis source arguments into structured JSON
#
# This script parses source specifications for /speckit.ui-synthesize
# and returns structured JSON for LLM consumption.
#
# Usage: ./parse-ui-sources.sh [OPTIONS]
#
# OPTIONS:
#   --context path:weight   Context file with Voice Weight (1-10)
#   --figma URL...          Figma URLs for visual verification
#   --components Name1,Name2 Filter to specific components
#   --output path/          Output directory for ui/*.md
#   --validate              Check files exist (default: true)
#   --no-validate           Skip file existence check
#   --json                  Output JSON format (default)
#   --help, -h              Show help message
#
# OUTPUT (JSON):
# {
#   "success": true,
#   "context_sources": [{"path": "ui-analysis.md", "weight": 9, "exists": true, "size_bytes": 1234}],
#   "figma_sources": [{"file_key": "ABC", "node_id": "123", "url": "..."}],
#   "component_filter": ["MainNav", "ShareDialog"],
#   "output_dir": "specs/008/ui/",
#   "stats": {"total_context_files": 1, "total_size_kb": 45},
#   "warnings": [],
#   "errors": []
# }

set -e

# Source common functions
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/common.sh" ]]; then
    source "$SCRIPT_DIR/common.sh"
fi

# Defaults
JSON_MODE=true
VALIDATE=true
BASE_DIR=""

# Arrays for results
declare -a CONTEXT_SOURCES=()
declare -a FIGMA_SOURCES=()
declare -a COMPONENT_FILTER=()
declare -a WARNINGS=()
declare -a ERRORS=()
OUTPUT_DIR=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --context)
            # Parse path:weight format
            if [[ "$2" =~ ^(.+):([0-9]+)$ ]]; then
                CONTEXT_PATH="${BASH_REMATCH[1]}"
                CONTEXT_WEIGHT="${BASH_REMATCH[2]}"
            else
                CONTEXT_PATH="$2"
                CONTEXT_WEIGHT=5
            fi

            # Clamp weight to 1-10
            if [[ "$CONTEXT_WEIGHT" -lt 1 ]]; then
                CONTEXT_WEIGHT=1
                WARNINGS+=("Context weight clamped to 1")
            elif [[ "$CONTEXT_WEIGHT" -gt 10 ]]; then
                CONTEXT_WEIGHT=10
                WARNINGS+=("Context weight clamped to 10")
            fi

            CONTEXT_SOURCES+=("$CONTEXT_PATH:$CONTEXT_WEIGHT")
            shift 2
            ;;
        --figma)
            shift
            # Collect all following args until next option
            while [[ $# -gt 0 ]] && [[ ! "$1" =~ ^-- ]]; do
                FIGMA_SOURCES+=("$1")
                shift
            done
            ;;
        --components)
            # Split comma-separated list
            IFS=',' read -ra COMPONENT_FILTER <<< "$2"
            # Trim whitespace from each component
            for i in "${!COMPONENT_FILTER[@]}"; do
                COMPONENT_FILTER[$i]=$(echo "${COMPONENT_FILTER[$i]}" | xargs)
            done
            shift 2
            ;;
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --json)
            JSON_MODE=true
            shift
            ;;
        --validate)
            VALIDATE=true
            shift
            ;;
        --no-validate)
            VALIDATE=false
            shift
            ;;
        --help|-h)
            cat << 'EOF'
Usage: parse-ui-sources.sh [OPTIONS]

Parse UI synthesis source arguments into structured JSON.

OPTIONS:
  --context path:weight   Context file with Voice Weight (1-10)
  --figma URL...          Figma URLs for visual verification
  --components Name1,Name2 Filter to specific components
  --output path/          Output directory for ui/*.md
  --validate              Check files exist (default)
  --no-validate           Skip file existence check
  --json                  Output JSON format (default)
  --help, -h              Show this help

EXAMPLES:
  ./parse-ui-sources.sh --context ui-analysis.md:9 --output specs/008/ui/
  ./parse-ui-sources.sh --context ui-analysis.md:9 --figma "https://figma.com/file/ABC"
  ./parse-ui-sources.sh --context ui-analysis.md:9 --components MainNav,ShareDialog

EOF
            exit 0
            ;;
        *)
            WARNINGS+=("Unknown option: $1")
            shift
            ;;
    esac
done

# Set base directory
if [[ -z "$BASE_DIR" ]]; then
    if type get_repo_root &>/dev/null; then
        BASE_DIR=$(get_repo_root)
    elif git rev-parse --show-toplevel >/dev/null 2>&1; then
        BASE_DIR=$(git rev-parse --show-toplevel)
    else
        BASE_DIR=$(pwd)
    fi
fi

# Security: Check for path traversal attempts
is_safe_path() {
    local path="$1"

    # Block explicit traversal patterns
    if [[ "$path" == *".."* ]]; then
        return 1
    fi

    # Allow absolute paths but verify they exist
    if [[ "$path" == /* ]]; then
        return 0
    fi

    # For relative paths, verify they stay within BASE_DIR
    local full_path="$BASE_DIR/$path"
    if [[ -e "$full_path" ]]; then
        local canonical
        canonical=$(realpath "$full_path" 2>/dev/null || readlink -f "$full_path" 2>/dev/null || echo "$full_path")
        if [[ "$canonical" != "$BASE_DIR"* ]]; then
            return 1
        fi
    fi

    return 0
}

# Parse Figma URL to extract file_key and node_id
parse_figma_url() {
    local url="$1"
    local file_key=""
    local node_id=""

    # Pattern: figma.com/file/{file_key}...
    if [[ "$url" =~ figma\.com/(file|design)/([a-zA-Z0-9]+) ]]; then
        file_key="${BASH_REMATCH[2]}"
    fi

    # Pattern: node-id={node_id} or ?node-id={node_id}
    if [[ "$url" =~ node-id=([0-9:%-]+) ]]; then
        node_id="${BASH_REMATCH[1]}"
        # URL decode %3A to :
        node_id="${node_id//%3A/:}"
        node_id="${node_id//-/:}"
    fi

    echo "$file_key|$node_id"
}

# Get file info (size, exists)
get_file_info() {
    local path="$1"
    local full_path

    # Handle absolute vs relative paths
    if [[ "$path" == /* ]]; then
        full_path="$path"
    else
        full_path="$BASE_DIR/$path"
    fi

    if [[ -f "$full_path" ]]; then
        local size=$(stat -c%s "$full_path" 2>/dev/null || stat -f%z "$full_path" 2>/dev/null || echo "0")
        echo "$size|true"
    else
        echo "0|false"
    fi
}

# Validate required arguments
if [[ ${#CONTEXT_SOURCES[@]} -eq 0 ]]; then
    ERRORS+=("No context file provided. Use --context path:weight")
fi

# Process context sources
total_size=0
context_json="["
first=true

for source in "${CONTEXT_SOURCES[@]}"; do
    IFS=':' read -r path weight <<< "$source"

    # Security check
    if ! is_safe_path "$path"; then
        ERRORS+=("Blocked unsafe path: $path")
        continue
    fi

    # Get file info
    file_info=$(get_file_info "$path")
    IFS='|' read -r size exists <<< "$file_info"

    # Validation
    if [[ "$VALIDATE" == "true" ]] && [[ "$exists" == "false" ]]; then
        ERRORS+=("Context file not found: $path")
    fi

    # Size warning
    size_kb=$((size / 1024))
    if [[ $size_kb -gt 50 ]]; then
        WARNINGS+=("Context file '$path' is ${size_kb}KB (>50KB). Consider chunking.")
    fi

    total_size=$((total_size + size))

    [[ "$first" != "true" ]] && context_json+=","
    first=false

    context_json+="{\"path\":\"$path\",\"weight\":$weight,\"exists\":$exists,\"size_bytes\":$size}"
done
context_json+="]"

# Process Figma sources
figma_json="["
first=true

for url in "${FIGMA_SOURCES[@]}"; do
    parsed=$(parse_figma_url "$url")
    IFS='|' read -r file_key node_id <<< "$parsed"

    if [[ -z "$file_key" ]]; then
        WARNINGS+=("Could not parse Figma file key from: $url")
        continue
    fi

    [[ "$first" != "true" ]] && figma_json+=","
    first=false

    # Escape special chars in URL
    escaped_url="${url//\"/\\\"}"

    node_id_json="null"
    [[ -n "$node_id" ]] && node_id_json="\"$node_id\""

    figma_json+="{\"file_key\":\"$file_key\",\"node_id\":$node_id_json,\"url\":\"$escaped_url\"}"
done
figma_json+="]"

# Process component filter
components_json="["
first=true

for comp in "${COMPONENT_FILTER[@]}"; do
    [[ -z "$comp" ]] && continue
    [[ "$first" != "true" ]] && components_json+=","
    first=false
    components_json+="\"$comp\""
done
components_json+="]"

# Validate output directory
output_json="null"
if [[ -n "$OUTPUT_DIR" ]]; then
    output_json="\"$OUTPUT_DIR\""

    # Check if parent directory exists (output dir may be created)
    parent_dir=$(dirname "$OUTPUT_DIR")
    if [[ ! -d "$BASE_DIR/$parent_dir" ]] && [[ ! -d "$parent_dir" ]]; then
        WARNINGS+=("Output parent directory does not exist: $parent_dir")
    fi
fi

# Build warnings JSON
warnings_json="["
first=true
for w in "${WARNINGS[@]}"; do
    [[ "$first" != "true" ]] && warnings_json+=","
    first=false
    escaped_w="${w//\"/\\\"}"
    warnings_json+="\"$escaped_w\""
done
warnings_json+="]"

# Build errors JSON
errors_json="["
first=true
for e in "${ERRORS[@]}"; do
    [[ "$first" != "true" ]] && errors_json+=","
    first=false
    escaped_e="${e//\"/\\\"}"
    errors_json+="\"$escaped_e\""
done
errors_json+="]"

# Determine success
success="true"
if [[ ${#ERRORS[@]} -gt 0 ]]; then
    success="false"
fi

# Stats
total_size_kb=$((total_size / 1024))
total_context_files=${#CONTEXT_SOURCES[@]}

# Output JSON
cat << EOF
{
  "success": $success,
  "context_sources": $context_json,
  "figma_sources": $figma_json,
  "component_filter": $components_json,
  "output_dir": $output_json,
  "stats": {
    "total_context_files": $total_context_files,
    "total_size_kb": $total_size_kb
  },
  "base_dir": "$BASE_DIR",
  "warnings": $warnings_json,
  "errors": $errors_json
}
EOF

# Exit with error if any errors
if [[ ${#ERRORS[@]} -gt 0 ]]; then
    exit 1
fi
