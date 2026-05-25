#!/usr/bin/env bash

# Parse synthesize source arguments into structured JSON
#
# This script parses the source specification syntax used by /speckit.synthesize
# and returns structured JSON for LLM consumption.
#
# Usage: ./parse-sources.sh [OPTIONS] <sources...>
#
# INPUT FORMATS:
#   file.md           → weight=5, order=auto
#   file.md:8         → weight=8, order=auto
#   file.md:8:1       → weight=8, order=1
#   folder/:5         → expand all .md, weight=5 each
#   "search query"    → returns as search_query for LLM processing
#   *.md:6            → glob pattern expansion
#
# OPTIONS:
#   --json            Output JSON format (default)
#   --validate        Check files exist (default: true)
#   --no-validate     Skip file existence check
#   --max-sources N   Limit sources (default: 10, max: 15)
#   --base-dir DIR    Base directory for relative paths
#   --help, -h        Show help message
#
# OUTPUT (JSON):
# {
#   "success": true,
#   "sources": [
#     {"path": "req.md", "weight": 8, "order": 1, "type": "file", "exists": true, "size_bytes": 1234}
#   ],
#   "search_queries": ["architecture docs"],
#   "folders": [{"path": "notes/", "weight": 5, "files": ["a.md", "b.md"]}],
#   "stats": {"total_files": 5, "total_size_kb": 45},
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
MAX_SOURCES=10
HARD_MAX=15
BASE_DIR=""

# Arrays for results
declare -a SOURCES=()
declare -a SEARCH_QUERIES=()
declare -a FOLDERS=()
declare -a WARNINGS=()
declare -a ERRORS=()
declare -a RAW_ARGS=()

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
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
        --max-sources)
            MAX_SOURCES="$2"
            if [[ "$MAX_SOURCES" -gt "$HARD_MAX" ]]; then
                WARNINGS+=("max-sources clamped to $HARD_MAX")
                MAX_SOURCES=$HARD_MAX
            fi
            shift 2
            ;;
        --base-dir)
            BASE_DIR="$2"
            shift 2
            ;;
        --help|-h)
            cat << 'EOF'
Usage: parse-sources.sh [OPTIONS] <sources...>

Parse synthesize source arguments into structured JSON.

INPUT FORMATS:
  file.md           → weight=5 (default), order=auto
  file.md:8         → weight=8, order=auto
  file.md:8:1       → weight=8, order=1
  folder/:5         → expand all .md files, weight=5 each
  "search query"    → semantic search (passed to LLM)
  *.md:6            → glob pattern with weight

OPTIONS:
  --json            Output JSON format (default)
  --validate        Check files exist (default)
  --no-validate     Skip file existence check
  --max-sources N   Limit sources (default: 10, max: 15)
  --base-dir DIR    Base directory for relative paths
  --help, -h        Show this help

EXAMPLES:
  ./parse-sources.sh requirements.md:9 notes.md:3
  ./parse-sources.sh --max-sources 5 drafts/:5 "API docs"
  ./parse-sources.sh --base-dir /path/to/project spec.md:10:1

EOF
            exit 0
            ;;
        -*)
            ERRORS+=("Unknown option: $1")
            shift
            ;;
        *)
            RAW_ARGS+=("$1")
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
# Returns: 0 if safe, 1 if unsafe
is_safe_path() {
    local path="$1"
    
    # Block explicit traversal patterns
    if [[ "$path" == *".."* ]]; then
        return 1
    fi
    
    # Block absolute paths (must be relative to BASE_DIR)
    if [[ "$path" == /* ]]; then
        return 1
    fi
    
    # If file/dir exists, verify it stays within BASE_DIR
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

# Helper: Parse single source argument
# Returns: path, weight, order, type
parse_source_arg() {
    local arg="$1"
    local path=""
    local weight=5
    local order=""
    local source_type="file"

    # Check if it's a quoted search query
    if [[ "$arg" =~ ^\"(.*)\"$ ]] || [[ "$arg" =~ ^\'(.*)\'$ ]]; then
        echo "search:${BASH_REMATCH[1]}"
        return
    fi

    # Check if it's a folder (ends with /)
    if [[ "$arg" =~ ^(.+)/:([0-9]+)$ ]]; then
        # folder/:weight
        path="${BASH_REMATCH[1]}/"
        weight="${BASH_REMATCH[2]}"
        source_type="folder"
    elif [[ "$arg" =~ ^(.+)/$ ]]; then
        # folder/ (no weight)
        path="$arg"
        source_type="folder"
    elif [[ "$arg" =~ ^(.+):([0-9]+):([0-9]+)$ ]]; then
        # path:weight:order
        path="${BASH_REMATCH[1]}"
        weight="${BASH_REMATCH[2]}"
        order="${BASH_REMATCH[3]}"
    elif [[ "$arg" =~ ^(.+):([0-9]+)$ ]]; then
        # path:weight
        path="${BASH_REMATCH[1]}"
        weight="${BASH_REMATCH[2]}"
    else
        # just path
        path="$arg"
    fi

    # Clamp weight to 1-10
    if [[ "$weight" -lt 1 ]]; then
        weight=1
    elif [[ "$weight" -gt 10 ]]; then
        weight=10
    fi

    # Check for glob pattern
    if [[ "$path" == *"*"* ]]; then
        source_type="glob"
    fi

    echo "$source_type:$path:$weight:$order"
}

# Helper: Expand folder to list of .md files
expand_folder() {
    local folder="$1"
    local full_path="$BASE_DIR/$folder"

    if [[ ! -d "$full_path" ]]; then
        return
    fi

    find "$full_path" -maxdepth 1 -name "*.md" -type f 2>/dev/null | while read -r file; do
        basename "$file"
    done
}

# Helper: Expand glob pattern
expand_glob() {
    local pattern="$1"
    local full_pattern="$BASE_DIR/$pattern"

    # Use nullglob to handle no matches
    shopt -s nullglob
    for file in $full_pattern; do
        if [[ -f "$file" ]]; then
            # Return relative path from base
            get_relative_path "$file"
        fi
    done
    shopt -u nullglob
}

# Helper: Get file info (size, mtime in ISO 8601, exists)
# Output format: size|mtime|exists (using | as delimiter to avoid conflict with : in timestamps)
get_file_info() {
    local path="$1"
    local full_path="$BASE_DIR/$path"

    if [[ -f "$full_path" ]]; then
        local size=$(stat -c%s "$full_path" 2>/dev/null || stat -f%z "$full_path" 2>/dev/null || echo "0")
        # ISO 8601 format: try GNU date first, then BSD date
        local mtime=$(date -u -r "$full_path" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
                      stat -c %Y "$full_path" 2>/dev/null | xargs -I{} date -u -d @{} +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
                      echo "")
        echo "$size|$mtime|true"
    else
        echo "0||false"
    fi
}

# Helper: Get relative path (portable realpath alternative)
get_relative_path() {
    local file="$1"
    if command -v realpath &>/dev/null; then
        realpath --relative-to="$BASE_DIR" "$file" 2>/dev/null
    elif command -v grealpath &>/dev/null; then
        # macOS with coreutils installed
        grealpath --relative-to="$BASE_DIR" "$file" 2>/dev/null
    else
        # Fallback: use Python or pure bash
        python3 -c "import os.path; print(os.path.relpath('$file', '$BASE_DIR'))" 2>/dev/null || \
        echo "${file#$BASE_DIR/}"
    fi
}

# Process all arguments
total_files=0
total_size=0
declare -A seen_files  # For deduplication

for arg in "${RAW_ARGS[@]}"; do
    parsed=$(parse_source_arg "$arg")

    IFS=':' read -r source_type path weight order <<< "$parsed"

    # Security: validate path before processing
    if [[ "$source_type" != "search" ]]; then
        if ! is_safe_path "$path"; then
            ERRORS+=("Blocked unsafe path: $path (path traversal or escape attempt)")
            continue
        fi
    fi

    case "$source_type" in
        search)
            SEARCH_QUERIES+=("$path")
            ;;
        folder)
            folder_files=()
            while IFS= read -r file; do
                [[ -n "$file" ]] && folder_files+=("$file")
            done < <(expand_folder "$path")

            if [[ ${#folder_files[@]} -eq 0 ]]; then
                WARNINGS+=("Folder '$path' contains no .md files")
            else
                # Add folder entry with file list
                folder_json="{\"path\":\"$path\",\"weight\":$weight,\"files\":["
                first=true
                for f in "${folder_files[@]}"; do
                    full_file_path="${path}${f}"
                    if [[ -z "${seen_files[$full_file_path]}" ]]; then
                        seen_files[$full_file_path]=1

                        file_info=$(get_file_info "$full_file_path")
                        IFS='|' read -r size mtime exists <<< "$file_info"

                        if [[ "$first" != "true" ]]; then
                            folder_json+=","
                        fi
                        folder_json+="\"$f\""
                        first=false

                        # Format mtime for JSON (escape empty as null)
                        mtime_json="null"
                        [[ -n "$mtime" ]] && mtime_json="\"$mtime\""

                        # Add as individual source
                        source_json="{\"path\":\"$full_file_path\",\"weight\":$weight,\"order\":null,\"type\":\"file\",\"from_folder\":\"$path\",\"exists\":$exists,\"size_bytes\":$size,\"modified_time\":$mtime_json}"
                        SOURCES+=("$source_json")

                        ((total_files++)) || true
                        ((total_size+=size)) || true

                        # Check size warning
                        size_kb=$((size / 1024))
                        if [[ $size_kb -gt 20 ]]; then
                            WARNINGS+=("File '$full_file_path' is ${size_kb}KB (>20KB)")
                        fi
                    fi
                done
                folder_json+="]}"
                FOLDERS+=("$folder_json")
            fi
            ;;
        glob)
            while IFS= read -r file; do
                if [[ -n "$file" ]] && [[ -z "${seen_files[$file]}" ]]; then
                    seen_files[$file]=1

                    file_info=$(get_file_info "$file")
                    IFS='|' read -r size mtime exists <<< "$file_info"

                    order_json="null"
                    [[ -n "$order" ]] && order_json="$order"

                    # Format mtime for JSON
                    mtime_json="null"
                    [[ -n "$mtime" ]] && mtime_json="\"$mtime\""

                    source_json="{\"path\":\"$file\",\"weight\":$weight,\"order\":$order_json,\"type\":\"file\",\"from_glob\":\"$path\",\"exists\":$exists,\"size_bytes\":$size,\"modified_time\":$mtime_json}"
                    SOURCES+=("$source_json")

                    ((total_files++)) || true
                    ((total_size+=size)) || true
                fi
            done < <(expand_glob "$path")
            ;;
        file)
            if [[ -z "${seen_files[$path]}" ]]; then
                seen_files[$path]=1

                file_info=$(get_file_info "$path")
                IFS='|' read -r size mtime exists <<< "$file_info"

                order_json="null"
                [[ -n "$order" ]] && order_json="$order"

                # Format mtime for JSON
                mtime_json="null"
                [[ -n "$mtime" ]] && mtime_json="\"$mtime\""

                source_json="{\"path\":\"$path\",\"weight\":$weight,\"order\":$order_json,\"type\":\"file\",\"exists\":$exists,\"size_bytes\":$size,\"modified_time\":$mtime_json}"
                SOURCES+=("$source_json")

                ((total_files++)) || true
                ((total_size+=size)) || true

                # Validation
                if [[ "$VALIDATE" == "true" ]] && [[ "$exists" == "false" ]]; then
                    WARNINGS+=("File not found: $path")
                fi

                # Check size warning
                size_kb=$((size / 1024))
                if [[ $size_kb -gt 20 ]]; then
                    WARNINGS+=("File '$path' is ${size_kb}KB (>20KB)")
                fi
            else
                WARNINGS+=("Duplicate source ignored: $path")
            fi
            ;;
    esac
done

# Check max sources limit
if [[ $total_files -gt $MAX_SOURCES ]]; then
    ERRORS+=("Too many sources ($total_files). Max allowed: $MAX_SOURCES. Use --max-sources to adjust.")
fi

# Check if any sources provided
if [[ $total_files -eq 0 ]] && [[ ${#SEARCH_QUERIES[@]} -eq 0 ]]; then
    ERRORS+=("No valid sources provided")
fi

# Build JSON output
success="true"
if [[ ${#ERRORS[@]} -gt 0 ]]; then
    success="false"
fi

# Sources array
sources_json="["
first=true
for src in "${SOURCES[@]}"; do
    if [[ "$first" != "true" ]]; then
        sources_json+=","
    fi
    sources_json+="$src"
    first=false
done
sources_json+="]"

# Search queries array
queries_json="["
first=true
for q in "${SEARCH_QUERIES[@]}"; do
    if [[ "$first" != "true" ]]; then
        queries_json+=","
    fi
    queries_json+="\"$q\""
    first=false
done
queries_json+="]"

# Folders array
folders_json="["
first=true
for f in "${FOLDERS[@]}"; do
    if [[ "$first" != "true" ]]; then
        folders_json+=","
    fi
    folders_json+="$f"
    first=false
done
folders_json+="]"

# Warnings array
warnings_json="["
first=true
for w in "${WARNINGS[@]}"; do
    if [[ "$first" != "true" ]]; then
        warnings_json+=","
    fi
    # Escape quotes in warning message
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

# Stats
total_size_kb=$((total_size / 1024))

# Output JSON
cat << EOF
{
  "success": $success,
  "sources": $sources_json,
  "search_queries": $queries_json,
  "folders": $folders_json,
  "stats": {
    "total_files": $total_files,
    "total_size_kb": $total_size_kb,
    "max_sources": $MAX_SOURCES
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
