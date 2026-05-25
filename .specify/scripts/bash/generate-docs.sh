#!/usr/bin/env bash
# Generate documentation from source files (commands, agents, scripts).
#
# Usage: ./generate-docs.sh [OPTIONS]
#
# OPTIONS:
#   --output-dir <path>   Output directory (default: docs/)
#   --check               Check mode - fail if docs outdated
#   --help                Show help message

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults
OUTPUT_DIR=""
CHECK_MODE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --check)
            CHECK_MODE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $(basename "$0") [OPTIONS]"
            echo ""
            echo "OPTIONS:"
            echo "  --output-dir <path>   Output directory (default: docs/)"
            echo "  --check               Check mode - fail if docs outdated"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Find repo root
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

if [[ -z "$OUTPUT_DIR" ]]; then
    OUTPUT_DIR="$REPO_ROOT/docs"
fi

COMMANDS_DIR="$OUTPUT_DIR/commands"
AGENTS_DIR="$OUTPUT_DIR/agents"
SCRIPTS_DIR="$OUTPUT_DIR/scripts"
ADR_DIR="$OUTPUT_DIR/adr"

# Create directories
if [[ "$CHECK_MODE" == false ]]; then
    mkdir -p "$COMMANDS_DIR" "$AGENTS_DIR" "$SCRIPTS_DIR" "$ADR_DIR"
fi

# Parse YAML front-matter from markdown
parse_yaml_front_matter() {
    local file="$1"
    local content=$(cat "$file")

    local description=""
    local handoffs="[]"

    # Check for YAML front-matter
    if [[ "$content" =~ ^---[[:space:]]*(.*)[[:space:]]*--- ]]; then
        local yaml="${BASH_REMATCH[1]}"

        # Extract description
        if [[ "$yaml" =~ description:[[:space:]]*(.+) ]]; then
            description="${BASH_REMATCH[1]}"
            description=$(echo "$description" | sed 's/^"//' | sed 's/"$//' | head -1)
        fi

        # Extract handoffs (simplified)
        while IFS= read -r label; do
            if [[ -n "$label" ]]; then
                handoffs=$(echo "$handoffs" | jq --arg l "$label" '. + [{"label": $l}]')
            fi
        done < <(echo "$yaml" | grep -oE 'label:\s*(.+)' | sed 's/label:\s*//' | sed 's/^"//' | sed 's/"$//')
    fi

    jq -n --arg d "$description" --argjson h "$handoffs" '{description: $d, handoffs: $h}'
}

# Generate command docs
generate_command_docs() {
    local commands_src="$REPO_ROOT/.claude/commands"
    local count=0

    if [[ ! -d "$commands_src" ]]; then
        echo "0"
        return
    fi

    local index_content="# Commands Reference\n\n| Command | Description | Handoffs |\n|---------|-------------|----------|\n"

    for file in "$commands_src"/speckit.*.md; do
        [[ ! -f "$file" ]] && continue

        local filename=$(basename "$file")
        local name=$(echo "$filename" | sed 's/^speckit\.//' | sed 's/\.md$//')
        local meta=$(parse_yaml_front_matter "$file")
        local description=$(echo "$meta" | jq -r '.description // ""')
        local handoffs=$(echo "$meta" | jq -r '.handoffs | map(.label) | join(", ") // "-"')

        [[ -z "$handoffs" ]] && handoffs="-"

        # Generate individual doc
        if [[ "$CHECK_MODE" == false ]]; then
            cat > "$COMMANDS_DIR/$name.md" << EOF
# /speckit.$name

> $description

**Source:** [.claude/commands/$filename](../../.claude/commands/$filename)
EOF
        fi

        index_content+="| [/speckit.$name]($name.md) | $description | $handoffs |\n"
        count=$((count + 1))
    done

    if [[ "$CHECK_MODE" == false ]]; then
        echo -e "$index_content" > "$COMMANDS_DIR/_index.md"
    fi

    echo "$count"
}

# Generate agent docs
generate_agent_docs() {
    local agents_src="$REPO_ROOT/.github/agents"
    local count=0

    if [[ ! -d "$agents_src" ]]; then
        echo "0"
        return
    fi

    local index_content="# Agents Reference\n\n| Agent | Description | Handoffs |\n|-------|-------------|----------|\n"

    for file in "$agents_src"/speckit.*.md; do
        [[ ! -f "$file" ]] && continue
        [[ "$file" == *".draft.md" ]] && continue

        local filename=$(basename "$file")
        local name=$(echo "$filename" | sed 's/^speckit\.//' | sed 's/\.agent\.md$//' | sed 's/\.md$//')

        # Parse chatagent header
        local content=$(cat "$file")
        local description=""

        if [[ "$content" =~ description:[[:space:]]*\"([^\"]+)\" ]]; then
            description="${BASH_REMATCH[1]}"
        fi

        # Generate individual doc
        if [[ "$CHECK_MODE" == false ]]; then
            cat > "$AGENTS_DIR/$name.md" << EOF
# Agent: $name

> $description

**Source:** [.github/agents/$filename](../../.github/agents/$filename)
EOF
        fi

        index_content+="| [$name]($name.md) | $description | - |\n"
        count=$((count + 1))
    done

    if [[ "$CHECK_MODE" == false ]]; then
        echo -e "$index_content" > "$AGENTS_DIR/_index.md"
    fi

    echo "$count"
}

# Generate script docs
generate_script_docs() {
    local scripts_src="$REPO_ROOT/.specify/scripts/bash"
    local count=0

    if [[ ! -d "$scripts_src" ]]; then
        echo "0"
        return
    fi

    local index_content="# Scripts Reference\n\n| Script | Synopsis |\n|--------|----------|\n"

    for file in "$scripts_src"/*.sh; do
        [[ ! -f "$file" ]] && continue
        [[ "$(basename "$file")" == "common.sh" ]] && continue
        [[ "$(basename "$file")" == "generate-docs.sh" ]] && continue

        local filename=$(basename "$file")
        local name="${filename%.sh}"

        # Extract synopsis from comments
        local synopsis=$(head -5 "$file" | grep -E '^#' | grep -v '^#!/' | head -1 | sed 's/^#\s*//')

        # Generate individual doc
        if [[ "$CHECK_MODE" == false ]]; then
            cat > "$SCRIPTS_DIR/$name.md" << EOF
# $filename

> $synopsis

**Source:** [.specify/scripts/bash/$filename](../../.specify/scripts/bash/$filename)
EOF
        fi

        index_content+="| [$filename]($name.md) | $synopsis |\n"
        count=$((count + 1))
    done

    if [[ "$CHECK_MODE" == false ]]; then
        echo -e "$index_content" > "$SCRIPTS_DIR/_index.md"
    fi

    echo "$count"
}

# Generate ADR index
generate_adr_index() {
    local count=0

    if [[ ! -d "$ADR_DIR" ]]; then
        echo "0"
        return
    fi

    local index_content="# Architecture Decision Records\n\n| ADR | Title | Status | Date |\n|-----|-------|--------|------|\n"

    for file in "$ADR_DIR"/*.md; do
        [[ ! -f "$file" ]] && continue
        [[ "$(basename "$file")" == "_index.md" ]] && continue

        local filename=$(basename "$file")
        local name="${filename%.md}"

        local content=$(cat "$file")
        local title=""
        local status="Unknown"
        local date=""

        if [[ "$content" =~ ^#[[:space:]]+ADR-[0-9]+:[[:space:]]*(.+) ]]; then
            title="${BASH_REMATCH[1]}"
        fi

        if [[ "$content" =~ \*\*Status:\*\*[[:space:]]*([^[:space:]]+) ]]; then
            status="${BASH_REMATCH[1]}"
        fi

        if [[ "$content" =~ \*\*Date:\*\*[[:space:]]*([^[:space:]]+) ]]; then
            date="${BASH_REMATCH[1]}"
        fi

        index_content+="| [$name]($name.md) | $title | $status | $date |\n"
        count=$((count + 1))
    done

    if [[ "$CHECK_MODE" == false ]]; then
        echo -e "$index_content" > "$ADR_DIR/_index.md"
    fi

    echo "$count"
}

# Generate main index
generate_main_index() {
    local commands="$1"
    local agents="$2"
    local scripts="$3"
    local adrs="$4"

    if [[ "$CHECK_MODE" == false ]]; then
        cat > "$OUTPUT_DIR/index.md" << EOF
# spec-kit Documentation

Auto-generated reference documentation.

## Components

### [Commands](commands/_index.md)
$commands slash commands for Claude Code.

### [Agents](agents/_index.md)
$agents GitHub Copilot agents.

### [Scripts](scripts/_index.md)
$scripts Bash utility scripts.

### [ADR](adr/_index.md)
$adrs architecture decision records.

---

*Generated: $(date -u +"%Y-%m-%d %H:%M:%S")*
EOF
    fi
}

# Main
echo "Generating documentation..."

COMMANDS_COUNT=$(generate_command_docs)
echo "  Commands: $COMMANDS_COUNT"

AGENTS_COUNT=$(generate_agent_docs)
echo "  Agents: $AGENTS_COUNT"

SCRIPTS_COUNT=$(generate_script_docs)
echo "  Scripts: $SCRIPTS_COUNT"

ADR_COUNT=$(generate_adr_index)
echo "  ADRs: $ADR_COUNT"

generate_main_index "$COMMANDS_COUNT" "$AGENTS_COUNT" "$SCRIPTS_COUNT" "$ADR_COUNT"

echo ""
echo "Documentation generated in: $OUTPUT_DIR"
