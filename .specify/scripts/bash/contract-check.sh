#!/usr/bin/env bash
# Validate implementation against OpenAPI contracts.
#
# Usage: ./contract-check.sh --contracts-dir <path> --source-dir <path> [OPTIONS]
#
# OPTIONS:
#   --contracts-dir <path>   Path to contracts directory
#   --source-dir <path>      Path to source code directory
#   --endpoint <path>        Validate specific endpoint only
#   --output <format>        Output format: json, summary, issues (default: json)
#   --help                   Show help message

set -euo pipefail

# Defaults
CONTRACTS_DIR=""
SOURCE_DIR=""
ENDPOINT=""
OUTPUT="json"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --contracts-dir)
            CONTRACTS_DIR="$2"
            shift 2
            ;;
        --source-dir)
            SOURCE_DIR="$2"
            shift 2
            ;;
        --endpoint)
            ENDPOINT="$2"
            shift 2
            ;;
        --output)
            OUTPUT="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $(basename "$0") --contracts-dir <path> --source-dir <path> [OPTIONS]"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Validate
if [[ -z "$CONTRACTS_DIR" ]]; then
    echo '{"error": "Missing --contracts-dir argument"}' >&2
    exit 1
fi

if [[ -z "$SOURCE_DIR" ]]; then
    echo '{"error": "Missing --source-dir argument"}' >&2
    exit 1
fi

if [[ ! -d "$CONTRACTS_DIR" ]]; then
    echo "{\"error\": \"Contracts directory not found: $CONTRACTS_DIR\"}" >&2
    exit 1
fi

# Parse OpenAPI paths from YAML
parse_contract_paths() {
    local file="$1"
    local paths="[]"

    # Extract paths (simplified parsing)
    local in_paths=false
    while IFS= read -r line; do
        if [[ "$line" =~ ^paths: ]]; then
            in_paths=true
            continue
        fi

        if [[ "$in_paths" == true ]]; then
            # Check if we've moved to another top-level section
            if [[ "$line" =~ ^[a-z]+: && ! "$line" =~ ^[[:space:]] ]]; then
                break
            fi

            # Extract path (2 spaces indent)
            if [[ "$line" =~ ^[[:space:]]{2}(/[^:]+): ]]; then
                local path="${BASH_REMATCH[1]}"
                paths=$(echo "$paths" | jq --arg p "$path" '. + [{"path": $p, "methods": []}]')
            fi
        fi
    done < "$file"

    echo "$paths"
}

# Find route handlers in source code
find_handlers() {
    local source_dir="$1"
    local handlers="[]"

    # Search patterns for common frameworks
    local patterns=(
        # Express.js
        'router\.(get|post|put|patch|delete)\s*\(\s*["\x27]([^"\x27]+)["\x27]'
        'app\.(get|post|put|patch|delete)\s*\(\s*["\x27]([^"\x27]+)["\x27]'
        # FastAPI
        '@(app|router)\.(get|post|put|patch|delete)\s*\(\s*["\x27]([^"\x27]+)["\x27]'
        # NestJS
        '@(Get|Post|Put|Patch|Delete)\s*\(\s*["\x27]?([^"\x27)\s]*)["\x27]?\s*\)'
    )

    # Find source files
    local files=$(find "$source_dir" -type f \( -name "*.ts" -o -name "*.js" -o -name "*.py" \) \
        -not -path "*/node_modules/*" \
        -not -path "*/.git/*" \
        -not -path "*/dist/*" \
        -not -path "*/__pycache__/*" \
        -not -path "*test*" 2>/dev/null)

    for file in $files; do
        local content=$(cat "$file" 2>/dev/null || echo "")

        # Express/Fastify pattern
        while IFS= read -r match; do
            if [[ -n "$match" ]]; then
                local method=$(echo "$match" | grep -oE '\.(get|post|put|patch|delete)' | tr -d '.' | tr '[:lower:]' '[:upper:]')
                local path=$(echo "$match" | grep -oE '["\x27](/[^"\x27]*)["\x27]' | tr -d '"\x27')

                if [[ -n "$method" && -n "$path" ]]; then
                    handlers=$(echo "$handlers" | jq --arg m "$method" --arg p "$path" --arg f "$file" \
                        '. + [{"method": $m, "path": $p, "file": $f}]')
                fi
            fi
        done < <(echo "$content" | grep -oE '(router|app)\.(get|post|put|patch|delete)\s*\(\s*["\x27][^"\x27]+["\x27]' 2>/dev/null || true)

        # Decorator pattern (FastAPI, NestJS)
        while IFS= read -r match; do
            if [[ -n "$match" ]]; then
                local method=$(echo "$match" | grep -oiE '@(get|post|put|patch|delete)' | tr -d '@' | tr '[:lower:]' '[:upper:]')
                local path=$(echo "$match" | grep -oE '\(["\x27]?([^"\x27)]+)["\x27]?\)' | sed -E 's/\(["\x27]?([^"\x27)]+)["\x27]?\)/\1/')

                if [[ -n "$method" ]]; then
                    [[ -z "$path" || "$path" == "()" ]] && path="/"
                    [[ ! "$path" =~ ^/ ]] && path="/$path"

                    handlers=$(echo "$handlers" | jq --arg m "$method" --arg p "$path" --arg f "$file" \
                        '. + [{"method": $m, "path": $p, "file": $f}]')
                fi
            fi
        done < <(echo "$content" | grep -oE '@(Get|Post|Put|Patch|Delete)\s*\([^)]*\)' 2>/dev/null || true)
    done

    echo "$handlers" | jq 'unique_by(.method + .path)'
}

# Compare contract paths with handlers
CHECKED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
CONTRACTS="[]"
ALL_PATHS="[]"
ISSUES="[]"

# Parse all contracts
for yaml_file in "$CONTRACTS_DIR"/*.yaml "$CONTRACTS_DIR"/*.yml; do
    if [[ -f "$yaml_file" ]]; then
        local fname=$(basename "$yaml_file")
        local paths=$(parse_contract_paths "$yaml_file")

        CONTRACTS=$(echo "$CONTRACTS" | jq --arg f "$fname" --argjson p "$paths" '. + [{"file": $f, "paths": $p}]')
        ALL_PATHS=$(echo "$ALL_PATHS" | jq --argjson p "$paths" '. + $p')
    fi
done

# Find handlers
HANDLERS=$(find_handlers "$SOURCE_DIR")

# Compare
ENDPOINTS="[]"
TOTAL=0
IMPLEMENTED=0
MISSING=0

for path_entry in $(echo "$ALL_PATHS" | jq -c '.[]'); do
    local path=$(echo "$path_entry" | jq -r '.path')

    # Apply endpoint filter
    if [[ -n "$ENDPOINT" && "$path" != "$ENDPOINT" ]]; then
        continue
    fi

    # For each HTTP method (simplified - assume common methods)
    for method in GET POST PUT PATCH DELETE; do
        TOTAL=$((TOTAL + 1))

        # Convert OpenAPI path params to pattern
        local pattern=$(echo "$path" | sed 's/{[^}]*}/[^\/]+/g')

        # Find matching handler
        local matched=$(echo "$HANDLERS" | jq --arg m "$method" --arg p "^${pattern}$" \
            '[.[] | select(.method == $m and (.path | test($p)))] | length')

        local status="missing"
        if [[ "$matched" -gt 0 ]]; then
            status="implemented"
            IMPLEMENTED=$((IMPLEMENTED + 1))
        else
            MISSING=$((MISSING + 1))
            ISSUES=$(echo "$ISSUES" | jq --arg m "$method" --arg p "$path" \
                '. + [{"type": "missing_endpoint", "severity": "high", "endpoint": ($m + " " + $p), "message": ("Endpoint " + $m + " " + $p + " not implemented")}]')
        fi

        ENDPOINTS=$(echo "$ENDPOINTS" | jq --arg m "$method" --arg p "$path" --arg s "$status" \
            '. + [{"method": $m, "contract_path": $p, "status": $s}]')
    done
done

# Output
case "$OUTPUT" in
    summary)
        echo "Contract Check Summary"
        echo "======================"
        echo "Total Endpoints: $TOTAL"
        echo "Implemented: $IMPLEMENTED"
        echo "Missing: $MISSING"
        if [[ $(echo "$ISSUES" | jq 'length') -gt 0 ]]; then
            echo ""
            echo "Issues:"
            echo "$ISSUES" | jq -r '.[] | "  - [\(.severity | ascii_upcase)] \(.message)"'
        fi
        ;;
    issues)
        echo "$ISSUES" | jq '.'
        ;;
    *)
        jq -n \
            --arg contracts_dir "$CONTRACTS_DIR" \
            --arg source_dir "$SOURCE_DIR" \
            --arg checked_at "$CHECKED_AT" \
            --argjson contracts "$CONTRACTS" \
            --argjson endpoints "$ENDPOINTS" \
            --argjson issues "$ISSUES" \
            --argjson total "$TOTAL" \
            --argjson implemented "$IMPLEMENTED" \
            --argjson missing "$MISSING" \
            '{
                contracts_dir: $contracts_dir,
                source_dir: $source_dir,
                checked_at: $checked_at,
                contracts: $contracts,
                endpoints: $endpoints,
                issues: $issues,
                summary: {
                    total_endpoints: $total,
                    implemented: $implemented,
                    missing: $missing
                }
            }'
        ;;
esac
