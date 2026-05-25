#!/usr/bin/env bash
# Cache Source of Truth documents for verification workflow.
#
# Usage: ./cache-sot.sh --feature-dir <path> [OPTIONS]
#
# OPTIONS:
#   --feature-dir <path>   Path to feature directory
#   --refresh              Force refresh of cache even if not stale
#   --max-age <minutes>    Maximum age before cache is stale (default: 30)
#   --help                 Show help message

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults
FEATURE_DIR=""
REFRESH=false
MAX_AGE=30

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --feature-dir)
            FEATURE_DIR="$2"
            shift 2
            ;;
        --refresh)
            REFRESH=true
            shift
            ;;
        --max-age)
            MAX_AGE="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $(basename "$0") --feature-dir <path> [OPTIONS]"
            echo ""
            echo "OPTIONS:"
            echo "  --feature-dir <path>   Path to feature directory"
            echo "  --refresh              Force refresh of cache"
            echo "  --max-age <minutes>    Maximum age before stale (default: 30)"
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

if [[ ! -d "$FEATURE_DIR" ]]; then
    echo "{\"error\": \"Feature directory not found: $FEATURE_DIR\"}" >&2
    exit 1
fi

# Get file hash
get_file_hash() {
    local file="$1"
    if [[ -f "$file" ]]; then
        if command -v md5sum &> /dev/null; then
            md5sum "$file" | cut -d' ' -f1
        elif command -v md5 &> /dev/null; then
            md5 -q "$file"
        else
            echo "unknown"
        fi
    else
        echo ""
    fi
}

# Parse spec.md for requirements
parse_spec() {
    local path="$1"
    if [[ ! -f "$path" ]]; then
        echo "null"
        return
    fi

    local hash=$(get_file_hash "$path")
    local content=$(cat "$path")

    # Extract requirements (FR-XXX, NFR-XXX patterns)
    local requirements=$(echo "$content" | grep -E '^#+\s*(FR|NFR|REQ)-[0-9]+' | head -20 | jq -R -s 'split("\n") | map(select(length > 0)) | map({id: (. | capture("(?<id>(FR|NFR|REQ)-[0-9]+)") | .id), title: .})' 2>/dev/null || echo "[]")

    # Extract sections
    local sections=$(echo "$content" | grep -E '^##\s+' | sed 's/^##\s*//' | head -20 | jq -R -s 'split("\n") | map(select(length > 0))' 2>/dev/null || echo "[]")

    jq -n \
        --arg file "spec.md" \
        --arg hash "$hash" \
        --argjson sections "$sections" \
        --argjson requirements "$requirements" \
        '{file: $file, hash: $hash, sections: $sections, requirements: $requirements}'
}

# Parse data-model.md for entities
parse_data_model() {
    local path="$1"
    if [[ ! -f "$path" ]]; then
        echo "null"
        return
    fi

    local hash=$(get_file_hash "$path")
    local content=$(cat "$path")

    # Extract entity names
    local entities=$(echo "$content" | grep -E '^#{2,3}\s+\w+' | sed -E 's/^#{2,3}\s+//' | grep -vE '^(Overview|Introduction|Relationships|Notes)' | head -30 | jq -R -s 'split("\n") | map(select(length > 0)) | map({name: ., type: "entity"})' 2>/dev/null || echo "[]")

    jq -n \
        --arg file "data-model.md" \
        --arg hash "$hash" \
        --argjson entities "$entities" \
        '{file: $file, hash: $hash, entities: $entities}'
}

# Parse contracts/*.yaml
parse_contracts() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        echo "[]"
        return
    fi

    local contracts="[]"

    for yaml_file in "$dir"/*.yaml "$dir"/*.yml; do
        if [[ -f "$yaml_file" ]]; then
            local filename=$(basename "$yaml_file")
            local hash=$(get_file_hash "$yaml_file")

            # Extract paths
            local endpoints=$(grep -E '^\s{2}/[^:]+:' "$yaml_file" 2>/dev/null | sed -E 's/^\s+//' | sed 's/:$//' | jq -R -s 'split("\n") | map(select(length > 0)) | map({path: .})' 2>/dev/null || echo "[]")

            local contract=$(jq -n \
                --arg file "$filename" \
                --arg path "$yaml_file" \
                --arg hash "$hash" \
                --argjson endpoints "$endpoints" \
                '{file: $file, path: $path, hash: $hash, endpoints: $endpoints}')

            contracts=$(echo "$contracts" | jq --argjson c "$contract" '. + [$c]')
        fi
    done

    echo "$contracts"
}

# Parse plan.md
parse_plan() {
    local path="$1"
    if [[ ! -f "$path" ]]; then
        echo "null"
        return
    fi

    local hash=$(get_file_hash "$path")
    local content=$(cat "$path")

    # Extract phases
    local phases=$(echo "$content" | grep -E '^##\s+Phase\s+[0-9]+' | sed -E 's/^##\s+Phase\s+([0-9]+)[:\s]+(.+)/{"number":\1,"name":"\2"}/' | jq -s '.' 2>/dev/null || echo "[]")

    # Extract stories
    local stories=$(echo "$content" | grep -E '^#{2,3}\s+US[0-9]+' | sed -E 's/^#{2,3}\s+(US[0-9]+)[:\s]+(.+)/{"id":"\1","name":"\2"}/' | jq -s '.' 2>/dev/null || echo "[]")

    jq -n \
        --arg file "plan.md" \
        --arg hash "$hash" \
        --argjson phases "$phases" \
        --argjson stories "$stories" \
        '{file: $file, hash: $hash, phases: $phases, stories: $stories}'
}

# Build cache
SPEC_PATH="$FEATURE_DIR/spec.md"
DATA_MODEL_PATH="$FEATURE_DIR/data-model.md"
CONTRACTS_DIR="$FEATURE_DIR/contracts"
PLAN_PATH="$FEATURE_DIR/plan.md"

SPEC_DOC=$(parse_spec "$SPEC_PATH")
DATA_MODEL_DOC=$(parse_data_model "$DATA_MODEL_PATH")
CONTRACTS_DOC=$(parse_contracts "$CONTRACTS_DIR")
PLAN_DOC=$(parse_plan "$PLAN_PATH")

# Current timestamp
CACHED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
STALE_AFTER=$(date -u -d "+${MAX_AGE} minutes" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -v+${MAX_AGE}M +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "$CACHED_AT")

# Aggregate requirements
REQUIREMENTS="[]"
if [[ "$SPEC_DOC" != "null" ]]; then
    REQUIREMENTS=$(echo "$SPEC_DOC" | jq '.requirements // []')
fi

# Aggregate endpoints
ENDPOINTS="[]"
for contract in $(echo "$CONTRACTS_DOC" | jq -c '.[]'); do
    contract_endpoints=$(echo "$contract" | jq '.endpoints // []')
    ENDPOINTS=$(echo "$ENDPOINTS" | jq --argjson e "$contract_endpoints" '. + $e')
done

# Aggregate entities
ENTITIES="[]"
if [[ "$DATA_MODEL_DOC" != "null" ]]; then
    ENTITIES=$(echo "$DATA_MODEL_DOC" | jq '.entities // []')
fi

# Calculate content hash
ALL_HASHES=""
[[ "$SPEC_DOC" != "null" ]] && ALL_HASHES+=$(echo "$SPEC_DOC" | jq -r '.hash // ""')
[[ "$DATA_MODEL_DOC" != "null" ]] && ALL_HASHES+="|$(echo "$DATA_MODEL_DOC" | jq -r '.hash // ""')"
[[ "$PLAN_DOC" != "null" ]] && ALL_HASHES+="|$(echo "$PLAN_DOC" | jq -r '.hash // ""')"
for contract in $(echo "$CONTRACTS_DOC" | jq -c '.[]'); do
    ALL_HASHES+="|$(echo "$contract" | jq -r '.hash // ""')"
done

# Output
jq -n \
    --arg feature_dir "$FEATURE_DIR" \
    --arg cached_at "$CACHED_AT" \
    --arg stale_after "$STALE_AFTER" \
    --argjson spec "$SPEC_DOC" \
    --argjson data_model "$DATA_MODEL_DOC" \
    --argjson contracts "$CONTRACTS_DOC" \
    --argjson plan "$PLAN_DOC" \
    --argjson requirements "$REQUIREMENTS" \
    --argjson endpoints "$ENDPOINTS" \
    --argjson entities "$ENTITIES" \
    --arg content_hash "$ALL_HASHES" \
    '{
        feature_dir: $feature_dir,
        cached_at: $cached_at,
        stale_after: $stale_after,
        documents: {
            spec: $spec,
            data_model: $data_model,
            contracts: $contracts,
            plan: $plan
        },
        requirements: $requirements,
        endpoints: $endpoints,
        entities: $entities,
        content_hash: $content_hash
    }'
