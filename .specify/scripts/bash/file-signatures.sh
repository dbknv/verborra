#!/usr/bin/env bash
# Extract function/class signatures without implementation bodies.
#
# Usage: ./file-signatures.sh --path <path> [OPTIONS]
#
# OPTIONS:
#   --path <path>         Path to file or directory
#   --extensions <list>   Comma-separated extensions (default: .ts,.js,.py,.go)
#   --recursive           Process directories recursively
#   --max-files <n>       Maximum files to process (default: 50)
#   --help                Show help message

set -euo pipefail

# Defaults
PATH_ARG=""
EXTENSIONS=".ts,.js,.py,.go,.rs"
RECURSIVE=false
MAX_FILES=50

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --path)
            PATH_ARG="$2"
            shift 2
            ;;
        --extensions)
            EXTENSIONS="$2"
            shift 2
            ;;
        --recursive)
            RECURSIVE=true
            shift
            ;;
        --max-files)
            MAX_FILES="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $(basename "$0") --path <path> [OPTIONS]"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Validate
if [[ -z "$PATH_ARG" ]]; then
    echo '{"error": "Missing --path argument"}' >&2
    exit 1
fi

# Convert extensions to find pattern
EXT_PATTERN=""
IFS=',' read -ra EXT_ARRAY <<< "$EXTENSIONS"
for ext in "${EXT_ARRAY[@]}"; do
    ext=$(echo "$ext" | xargs)  # trim
    if [[ -n "$EXT_PATTERN" ]]; then
        EXT_PATTERN="$EXT_PATTERN -o"
    fi
    EXT_PATTERN="$EXT_PATTERN -name '*$ext'"
done

# Find files
if [[ -f "$PATH_ARG" ]]; then
    FILES=("$PATH_ARG")
else
    FIND_CMD="find \"$PATH_ARG\" -type f \( $EXT_PATTERN \) -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/dist/*' -not -path '*/__pycache__/*'"
    if [[ "$RECURSIVE" == false ]]; then
        FIND_CMD="$FIND_CMD -maxdepth 1"
    fi
    FILES=($(eval "$FIND_CMD" 2>/dev/null | head -n "$MAX_FILES"))
fi

# Extract signatures
RESULTS='{"processed": 0, "files": [], "total_signatures": 0}'
PROCESSED=0
TOTAL_SIGS=0

for file in "${FILES[@]}"; do
    [[ ! -f "$file" ]] && continue

    EXT="${file##*.}"
    CONTENT=$(cat "$file" 2>/dev/null || echo "")
    SIGNATURES="[]"
    MEMBERS="[]"

    case ".$EXT" in
        .ts|.tsx|.js|.jsx)
            # TypeScript/JavaScript
            while IFS= read -r sig; do
                [[ -n "$sig" ]] && SIGNATURES=$(echo "$SIGNATURES" | jq --arg s "$sig" '. + [$s]')
            done < <(echo "$CONTENT" | grep -E '^export\s+(async\s+)?function\s+\w+|^export\s+(default\s+)?class\s+\w+|^export\s+interface\s+\w+|^export\s+type\s+\w+\s*=' | head -30)
            ;;
        .py)
            # Python
            while IFS= read -r sig; do
                [[ -n "$sig" ]] && SIGNATURES=$(echo "$SIGNATURES" | jq --arg s "$sig" '. + [$s]')
            done < <(echo "$CONTENT" | grep -E '^(async\s+)?def\s+\w+|^class\s+\w+' | head -30)
            ;;
        .go)
            # Go
            while IFS= read -r sig; do
                [[ -n "$sig" ]] && SIGNATURES=$(echo "$SIGNATURES" | jq --arg s "$sig" '. + [$s]')
            done < <(echo "$CONTENT" | grep -E '^func\s+(\([^)]+\)\s*)?\w+|^type\s+\w+\s+(struct|interface)' | head -30)
            ;;
        .rs)
            # Rust
            while IFS= read -r sig; do
                [[ -n "$sig" ]] && SIGNATURES=$(echo "$SIGNATURES" | jq --arg s "$sig" '. + [$s]')
            done < <(echo "$CONTENT" | grep -E '^pub\s+(async\s+)?fn\s+\w+|^pub\s+struct\s+\w+|^pub\s+enum\s+\w+|^pub\s+trait\s+\w+' | head -30)
            ;;
    esac

    SIG_COUNT=$(echo "$SIGNATURES" | jq 'length')
    if [[ "$SIG_COUNT" -gt 0 ]]; then
        FILE_RESULT=$(jq -n \
            --arg path "$file" \
            --arg ext ".$EXT" \
            --argjson signatures "$SIGNATURES" \
            --argjson members "$MEMBERS" \
            '{path: $path, extension: $ext, signatures: $signatures, members: $members}')

        RESULTS=$(echo "$RESULTS" | jq --argjson f "$FILE_RESULT" '.files += [$f]')
        TOTAL_SIGS=$((TOTAL_SIGS + SIG_COUNT))
    fi

    PROCESSED=$((PROCESSED + 1))
done

# Update counts
RESULTS=$(echo "$RESULTS" | jq --argjson p "$PROCESSED" --argjson t "$TOTAL_SIGS" '.processed = $p | .total_signatures = $t')

echo "$RESULTS" | jq '.'
