#!/usr/bin/env bash
# Prepare directory structure for Figma asset download
# Actual download happens through Claude Code's Figma MCP integration
# Usage: ./download-figma-assets.sh --figma-url <url> --output-dir <path> [--format svg|png]

set -euo pipefail

# Source common functions
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# --- Configuration ---
FIGMA_URL=""
OUTPUT_DIR=""
FORMAT="svg"

# --- Functions ---

print_usage() {
    cat <<EOF
Usage: $(basename "$0") --figma-url <url> --output-dir <path> [--format svg|png]

Prepare directory structure for Figma asset download.
Actual asset download is performed by Claude Code using Figma MCP.

Options:
  --figma-url <url>     Figma file or frame URL (required)
  --output-dir <path>   Output directory for assets (required)
  --format <type>       Asset format: svg (default) or png

Examples:
  $(basename "$0") --figma-url "https://www.figma.com/file/ABC123/..." --output-dir specs/001-feature/ui/assets
  $(basename "$0") --figma-url "https://www.figma.com/design/ABC123/..." --output-dir ./assets --format png
EOF
}

extract_file_key() {
    local url="$1"

    # Handle both /file/ and /design/ URL patterns
    # https://www.figma.com/file/XXXXX/Name?...
    # https://www.figma.com/design/XXXXX/Name?...

    local key=""

    if [[ "$url" =~ /file/([^/\?]+) ]]; then
        key="${BASH_REMATCH[1]}"
    elif [[ "$url" =~ /design/([^/\?]+) ]]; then
        key="${BASH_REMATCH[1]}"
    fi

    echo "$key"
}

extract_node_id() {
    local url="$1"

    # Extract node-id from URL if present
    # ?node-id=123-456 or ?node-id=123:456

    if [[ "$url" =~ node-id=([^&]+) ]]; then
        echo "${BASH_REMATCH[1]}"
    fi
}

# --- Main ---

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --figma-url)
            FIGMA_URL="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --format)
            FORMAT="$2"
            shift 2
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            echo "Error: Unknown option: $1" >&2
            print_usage >&2
            exit 1
            ;;
    esac
done

# Validate required arguments
if [[ -z "$FIGMA_URL" ]]; then
    echo "Error: --figma-url is required" >&2
    print_usage >&2
    exit 1
fi

if [[ -z "$OUTPUT_DIR" ]]; then
    echo "Error: --output-dir is required" >&2
    print_usage >&2
    exit 1
fi

# Validate format
if [[ "$FORMAT" != "svg" && "$FORMAT" != "png" ]]; then
    echo "Error: --format must be 'svg' or 'png'" >&2
    exit 1
fi

# Extract Figma file key
FILE_KEY=$(extract_file_key "$FIGMA_URL")
if [[ -z "$FILE_KEY" ]]; then
    echo "Error: Could not extract Figma file key from URL" >&2
    echo "URL should be like: https://www.figma.com/file/XXXXX/..." >&2
    exit 1
fi

# Extract node ID if present
NODE_ID=$(extract_node_id "$FIGMA_URL")

# Create output directories
mkdir -p "$OUTPUT_DIR/icons"
mkdir -p "$OUTPUT_DIR/images"
mkdir -p "$OUTPUT_DIR/components"

echo "═══════════════════════════════════════════════════════════════"
echo "  Figma Asset Download Preparation"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Figma File Key: $FILE_KEY"
[[ -n "$NODE_ID" ]] && echo "Node ID: $NODE_ID"
echo "Output Directory: $OUTPUT_DIR"
echo "Format: $FORMAT"
echo ""
echo "───────────────────────────────────────────────────────────────"
echo ""
echo "Created directories:"
echo "  ✓ $OUTPUT_DIR/icons/"
echo "  ✓ $OUTPUT_DIR/images/"
echo "  ✓ $OUTPUT_DIR/components/"
echo ""

# Create manifest template
MANIFEST_FILE="$OUTPUT_DIR/manifest.json"
cat > "$MANIFEST_FILE" << EOF
{
  "figma_file_key": "$FILE_KEY",
  "figma_url": "$FIGMA_URL",
  "node_id": ${NODE_ID:+"\"$NODE_ID\""}${NODE_ID:-null},
  "format": "$FORMAT",
  "created_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "downloaded_at": null,
  "assets": []
}
EOF

echo "Created manifest: $MANIFEST_FILE"
echo ""
echo "───────────────────────────────────────────────────────────────"
echo ""
echo "NEXT STEPS:"
echo ""
echo "1. In Claude Code, run /speckit.ui with the Figma URL:"
echo "   /speckit.ui $FIGMA_URL"
echo ""
echo "2. Claude Code will use Figma MCP to:"
echo "   - Fetch component structure"
echo "   - Download assets to $OUTPUT_DIR"
echo "   - Update manifest.json with asset list"
echo ""
echo "3. After download, verify assets:"
echo "   ls -la $OUTPUT_DIR/icons/"
echo "   ls -la $OUTPUT_DIR/images/"
echo ""
echo "═══════════════════════════════════════════════════════════════"

# Output JSON for programmatic use
if [[ "${JSON_OUTPUT:-false}" == "true" ]]; then
    cat << EOF
{
  "status": "prepared",
  "file_key": "$FILE_KEY",
  "node_id": ${NODE_ID:+"\"$NODE_ID\""}${NODE_ID:-null},
  "output_dir": "$OUTPUT_DIR",
  "format": "$FORMAT",
  "manifest": "$MANIFEST_FILE",
  "directories": {
    "icons": "$OUTPUT_DIR/icons",
    "images": "$OUTPUT_DIR/images",
    "components": "$OUTPUT_DIR/components"
  }
}
EOF
fi
