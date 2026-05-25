#!/bin/bash
# graph-check.sh — Universal dead code detection via connectivity analysis
# 
# Usage: graph-check.sh <FEATURE_DIR> [SRC_DIR] [--mode universal|ui-extras]
#
# Modes:
#   universal (default) — checks .ts, .tsx, .py, .go for unused exports
#   ui-extras           — adds modal/popup trigger checks (TSX only)
#
# Output: JSON with issues
# {
#   "issues": [
#     {"type": "graph_unused_export", "name": "MyFunc", "file": "..."},
#     {"type": "graph_imported_not_used", "name": "MyFunc", "file": "..."},
#     {"type": "graph_missing_trigger", "name": "MyPopup", "file": "..."} // ui-extras only
#   ]
# }

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh" 2>/dev/null || true

FEATURE_DIR=""
SRC_DIR=""
MODE="universal"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --mode=*)
      MODE="${1#*=}"
      shift
      ;;
    --mode)
      shift
      MODE="$1"
      shift
      ;;
    --*)
      shift
      ;;
    *)
      if [[ -z "$FEATURE_DIR" ]]; then
        FEATURE_DIR="$1"
      elif [[ -z "$SRC_DIR" ]]; then
        SRC_DIR="$1"
      fi
      shift
      ;;
  esac
done

# Validate input
if [[ -z "$FEATURE_DIR" ]]; then
  echo '{"error": "FEATURE_DIR is required", "issues": []}' 
  exit 1
fi

# Auto-detect SRC_DIR if not provided
if [[ -z "$SRC_DIR" ]]; then
  if [[ -d "frontend/src" ]]; then
    SRC_DIR="frontend/src"
  elif [[ -d "src" ]]; then
    SRC_DIR="src"
  elif [[ -d "backend" ]]; then
    SRC_DIR="backend"
  else
    # Try to get from plan.md Project Structure
    if [[ -f "$FEATURE_DIR/plan.md" ]]; then
      SRC_DIR=$(grep -oP '(?<=frontend/|src/)src' "$FEATURE_DIR/plan.md" | head -1 || echo "src")
    fi
    SRC_DIR="${SRC_DIR:-src}"
  fi
fi

if [[ ! -d "$SRC_DIR" ]]; then
  echo "{\"error\": \"SRC_DIR not found: $SRC_DIR\", \"issues\": []}"
  exit 1
fi

# Determine file extensions based on mode
if [[ "$MODE" == "ui-extras" ]]; then
  EXTENSIONS="tsx"
else
  # Universal mode: all supported extensions
  EXTENSIONS="ts tsx py go"
fi

# Collect files from the feature
FILES=""

# Method 1: Find files mentioned in tasks.md as created
if [[ -f "$FEATURE_DIR/tasks.md" ]]; then
  for ext in $EXTENSIONS; do
    found=$(grep -oP "\S+\.$ext" "$FEATURE_DIR/tasks.md" 2>/dev/null | sed 's/`//g' | sort -u || true)
    FILES="$FILES $found"
  done
fi

# Method 2: If no files found, scan src directory
if [[ -z "$(echo $FILES | tr -d ' ')" ]]; then
  for ext in $EXTENSIONS; do
    found=$(find "$SRC_DIR" -name "*.$ext" -type f 2>/dev/null | head -50 || true)
    FILES="$FILES $found"
  done
fi

# Start JSON output
echo '{"issues": ['

FIRST_ISSUE=true

output_issue() {
  local type="$1"
  local name="$2"
  local file="$3"
  
  if [[ "$FIRST_ISSUE" == "false" ]]; then echo ","; fi
  FIRST_ISSUE=false
  echo -n "{\"type\": \"$type\", \"name\": \"$name\", \"file\": \"$file\"}"
}

for file in $FILES; do
  [[ -f "$file" ]] || continue
  
  # Skip files with @verify-ignore marker
  if grep -q "@verify-ignore" "$file" 2>/dev/null; then
    continue
  fi
  
  # Skip test files
  [[ "$file" == *".test."* ]] && continue
  [[ "$file" == *".spec."* ]] && continue
  [[ "$file" == *"__test__"* ]] && continue
  [[ "$file" == *"_test.go" ]] && continue
  [[ "$file" == *"test_"*.py ]] && continue
  
  # Get file extension
  ext="${file##*.}"
  
  # Extract exported names based on file type
  names=""
  case "$ext" in
    ts|tsx)
      # Skip pages/layouts (entry points)
      [[ "$file" == *"/pages/"* ]] && continue
      [[ "$file" == *"/app/"* ]] && continue
      [[ "$file" == *"Page.tsx" ]] && continue
      [[ "$file" == *"Layout.tsx" ]] && continue
      
      # Extract exported functions/classes/consts
      names=$(grep -oP 'export\s+(function|const|class)\s+\K[A-Za-z][A-Za-z0-9]*' "$file" 2>/dev/null || true)
      # Also default exports with name
      default_name=$(grep -oP 'export\s+default\s+(function|class)\s+\K[A-Za-z][A-Za-z0-9]*' "$file" 2>/dev/null || true)
      names="$names $default_name"
      ;;
    py)
      # Skip __init__.py (barrel)
      [[ "$file" == *"__init__.py" ]] && continue
      
      # Python: functions and classes at module level
      names=$(grep -oP '^(def|class)\s+\K[A-Za-z_][A-Za-z0-9_]*' "$file" 2>/dev/null || true)
      # Check if in __all__
      all_exports=$(grep -oP '__all__\s*=\s*\[\K[^\]]+' "$file" 2>/dev/null | tr -d "'" | tr -d '"' | tr ',' ' ' || true)
      if [[ -n "$all_exports" ]]; then
        names="$all_exports"
      fi
      ;;
    go)
      # Go: only exported (capitalized) functions and types
      names=$(grep -oP '^func\s+\K[A-Z][A-Za-z0-9]*' "$file" 2>/dev/null || true)
      type_names=$(grep -oP '^type\s+\K[A-Z][A-Za-z0-9]*' "$file" 2>/dev/null || true)
      names="$names $type_names"
      ;;
  esac
  
  for name in $names; do
    [[ -z "$name" ]] && continue
    
    # 1. Check if name is imported/used anywhere
    imports=""
    case "$ext" in
      ts|tsx)
        imports=$(grep -rlE "import.*[{,]\s*$name\s*[,}]|import\s+$name\s+from|from\s+['\"].*/$name['\"]" "$SRC_DIR" --include="*.ts" --include="*.tsx" 2>/dev/null || true)
        ;;
      py)
        imports=$(grep -rlE "from\s+\S+\s+import.*\b$name\b|import\s+\S+\.$name" "$SRC_DIR" --include="*.py" 2>/dev/null || true)
        ;;
      go)
        # Go uses package.Name pattern
        pkg_name=$(basename "$(dirname "$file")")
        imports=$(grep -rl "$pkg_name\.$name" "$SRC_DIR" --include="*.go" 2>/dev/null || true)
        ;;
    esac
    
    # Handle barrel exports for TS/TSX
    if [[ "$ext" == "ts" || "$ext" == "tsx" ]]; then
      if echo "$imports" | grep -q "index\.ts"; then
        barrel_files=$(echo "$imports" | grep "index\.ts" || true)
        for barrel in $barrel_files; do
          barrel_dir=$(dirname "$barrel")
          barrel_imports=$(grep -rl "from ['\"].*${barrel_dir}['\"]" "$SRC_DIR" --include="*.tsx" --include="*.ts" 2>/dev/null || true)
          imports=$(echo -e "$imports\n$barrel_imports" | grep -v "index\.ts" | sort -u)
        done
      fi
    fi
    
    # Handle __init__.py for Python
    if [[ "$ext" == "py" ]]; then
      if echo "$imports" | grep -q "__init__\.py"; then
        init_files=$(echo "$imports" | grep "__init__\.py" || true)
        for init in $init_files; do
          init_dir=$(dirname "$init")
          pkg_imports=$(grep -rl "from $init_dir" "$SRC_DIR" --include="*.py" 2>/dev/null || true)
          imports=$(echo -e "$imports\n$pkg_imports" | grep -v "__init__\.py" | sort -u)
        done
      fi
    fi
    
    # Remove self-imports
    imports=$(echo "$imports" | grep -v "$file" || true)
    
    if [[ -z "$imports" ]]; then
      output_issue "graph_unused_export" "$name" "$file"
      continue
    fi
    
    # 2. Check if actually used (not just imported)
    for parent in $imports; do
      [[ -f "$parent" ]] || continue
      
      case "$ext" in
        ts|tsx)
          # Check for JSX usage <Name, function call Name(, or reference {Name}
          if ! grep -qE "<$name[^a-zA-Z]|\{$name\}|$name\s*\(|$name\s*," "$parent" 2>/dev/null; then
            output_issue "graph_imported_not_used" "$name" "$parent"
          fi
          ;;
        py)
          # Check for function call or class instantiation
          if ! grep -qE "$name\s*\(|$name\s*\." "$parent" 2>/dev/null; then
            output_issue "graph_imported_not_used" "$name" "$parent"
          fi
          ;;
        go)
          # Already checked via package.Name pattern — if found, it's used
          ;;
      esac
    done
    
    # 3. UI-extras: Modal/Popup trigger check (TSX only)
    if [[ "$MODE" == "ui-extras" && "$ext" == "tsx" ]]; then
      is_modal=false
      if echo "$name" | grep -qE "Modal|Popup|Dialog|Drawer|Sheet"; then
        is_modal=true
      elif grep -qE "isOpen\s*[?:]|open\s*[?:].*boolean|visible\s*[?:]" "$file" 2>/dev/null; then
        is_modal=true
      fi
      
      if [[ "$is_modal" == "true" ]]; then
        for parent in $imports; do
          [[ -f "$parent" ]] || continue
          
          # Check for useState with boolean or useDisclosure
          if ! grep -qE "useState\s*\(\s*(true|false)\s*\)|useState<boolean>|useDisclosure" "$parent" 2>/dev/null; then
            # Only flag if component is actually used in this file
            if grep -qE "<$name[^a-zA-Z]" "$parent" 2>/dev/null; then
              output_issue "graph_missing_trigger" "$name" "$parent"
            fi
          fi
        done
      fi
    fi
  done
done

echo ']}'
