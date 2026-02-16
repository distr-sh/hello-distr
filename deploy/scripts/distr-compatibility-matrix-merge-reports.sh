#!/usr/bin/env bash
set -euo pipefail

# Merge per-version kubeconform JSON results into a unified cross-version report.
#
# Usage:
#   ./scripts/distr-compatibility-matrix-merge-reports.sh [REPORT_DIR]
#
# Reads all kubeconform-*.json files from REPORT_DIR (default: .)
# Produces compatibility-matrix.md with a cross-version compatibility matrix.

REPORT_DIR="${1:-.}"
REPORT="compatibility-matrix.md"

# Collect JSON files sorted by version
mapfile -t JSON_FILES < <(find "$REPORT_DIR" -name 'kubeconform-*.json' -type f | sort)

if [ ${#JSON_FILES[@]} -eq 0 ]; then
  echo "No kubeconform JSON files found in $REPORT_DIR"
  exit 1
fi

# Extract versions from filenames (kubeconform-1.32.0.json -> 1.32.0)
VERSIONS=()
for f in "${JSON_FILES[@]}"; do
  version=$(basename "$f" | sed 's/^kubeconform-//; s/\.json$//')
  VERSIONS+=("$version")
done

{
  echo "# Compatibility Matrix Test Report"
  echo ""
  echo "**Date:** $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "**Versions:** ${VERSIONS[*]}"
  echo ""

  # Check for any failures across all versions
  HAS_FAILURE=0
  for f in "${JSON_FILES[@]}"; do
    invalid=$(jq '.summary.invalid' "$f")
    errors=$(jq '.summary.errors' "$f")
    if [ "$invalid" -gt 0 ] || [ "$errors" -gt 0 ]; then
      HAS_FAILURE=1
    fi
  done

  echo "## Compatibility Matrix"
  echo ""

  # Header row
  header="| Kind | apiVersion | Name |"
  separator="|------|------------|------|"
  for v in "${VERSIONS[@]}"; do
    header+=" ${v} |"
    separator+="--------|"
  done
  echo "$header"
  echo "$separator"

  # Get sorted unique resource keys across all versions
  RESOURCE_KEYS=$(for f in "${JSON_FILES[@]}"; do
    jq -r '.resources[]? | "\(.kind)\t\(.version)\t\(.name)"' "$f"
  done | sort -u)

  # For each resource, look up its status in each version's JSON
  while IFS=$'\t' read -r kind apiversion name; do
    [ -z "$kind" ] && continue
    row="| ${kind} | ${apiversion} | ${name} |"
    for i in "${!JSON_FILES[@]}"; do
      status=$(jq -r --arg kind "$kind" --arg ver "$apiversion" --arg name "$name" \
        '.resources[]? | select(.kind == $kind and .version == $ver and .name == $name) | .status' \
        "${JSON_FILES[$i]}" | head -1)
      case "$status" in
        statusValid)   row+=" ✅ |" ;;
        statusSkipped) row+=" skip |" ;;
        "")            row+=" - |" ;;
        *)             row+=" ❌ |" ;;
      esac
    done
    echo "$row"
  done <<< "$RESOURCE_KEYS"

  echo ""

  # Per-version detail sections
  for i in "${!VERSIONS[@]}"; do
    version="${VERSIONS[$i]}"
    json_file="${JSON_FILES[$i]}"
    report_file="${REPORT_DIR}/kubeconform-report-${version}.md"

    echo "## Kubernetes ${version}"
    echo ""

    valid=$(jq '.summary.valid' "$json_file")
    invalid=$(jq '.summary.invalid' "$json_file")
    errors=$(jq '.summary.errors' "$json_file")
    skipped=$(jq '.summary.skipped' "$json_file")

    echo "| Status | Count |"
    echo "|--------|-------|"
    echo "| Valid | ${valid} |"
    echo "| Invalid | ${invalid} |"
    echo "| Errors | ${errors} |"
    echo "| Skipped | ${skipped} |"
    echo ""

    # Show issues if any
    if [ "$invalid" -gt 0 ] || [ "$errors" -gt 0 ]; then
      echo "### Issues"
      echo ""
      echo "| Resource | Kind | Message |"
      echo "|----------|------|---------|"
      jq -r '.resources[]? | select(.status == "statusInvalid" or .status == "statusError") | "| \(.name) | \(.kind) | \(.msg) |"' "$json_file"
      echo ""
    fi
  done

  echo "---"
  echo ""
  if [ "$HAS_FAILURE" -eq 1 ]; then
    echo "**Result: FAIL**"
  else
    echo "**Result: PASS**"
  fi
  echo ""
  echo "---"
  echo ""
  echo "*Generated with [kubeconform](https://github.com/yannh/kubeconform)*"
} > "$REPORT"

echo "Unified report written to $REPORT"
