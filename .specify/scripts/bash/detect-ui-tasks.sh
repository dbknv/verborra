#!/bin/bash
# detect-ui-tasks.sh - Detect which components need [UI] tasks
# Usage: ./detect-ui-tasks.sh --ui-dir path/to/ui [--json]

UI_DIR=""
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --ui-dir) UI_DIR="$2"; shift 2 ;;
    --json) JSON_OUTPUT=true; shift ;;
    *) shift ;;
  esac
done

if [ -z "$UI_DIR" ] || [ ! -d "$UI_DIR" ]; then
  echo "Error: --ui-dir required and must exist" >&2
  exit 1
fi

components_needing_ui=()

for spec in "$UI_DIR"/*.md; do
  [ -f "$spec" ] || continue
  [[ "$(basename "$spec")" == "_index.md" ]] && continue

  component_name=$(basename "$spec" .md)
  component_type=$(grep -m1 '\*\*Type\*\*:' "$spec" | sed 's/.*: *//' | tr -d '\r')
  figma_field=$(grep -m1 '\*\*Figma\*\*:' "$spec" | sed 's/.*: *//' | tr -d '\r')

  # Fallbacks for legacy files (without Type/Figma fields)
  component_type=${component_type:-"Molecule"}
  figma_field=${figma_field:-"unknown"}

  # Skip ONLY design system primitives: Atom + N/A Figma
  [[ "$component_type" == "Atom" && "$figma_field" == "N/A" ]] && continue

  components_needing_ui+=("$component_name")
done

if $JSON_OUTPUT; then
  printf '{"components":['
  first=true
  for c in "${components_needing_ui[@]}"; do
    $first || printf ','
    printf '"%s"' "$c"
    first=false
  done
  printf '],"count":%d}\n' "${#components_needing_ui[@]}"
else
  for c in "${components_needing_ui[@]}"; do
    echo "$c"
  done
fi
