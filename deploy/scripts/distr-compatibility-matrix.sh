#!/usr/bin/env bash
set -euo pipefail

# Validate the hello-distr Helm chart with kubeconform.
#
# Usage:
#   ./scripts/distr-compatibility-matrix.sh [VERSION]
#
# With VERSION:  validates against a single Kubernetes version (CI matrix mode).
#                Produces kubeconform-{VERSION}.json and compatibility-matrix-{VERSION}.md.
# Without args:  validates against all supported versions (local mode).
#                Produces per-version artifacts plus a unified compatibility-matrix.md.

CHART_DIR="deploy/charts/hello-distr"
ALL_VERSIONS=("1.32.0" "1.33.0" "1.34.0" "1.35.0")
SCHEMA_LOCATION='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

run_kubeconform() {
  if command -v kubeconform &>/dev/null; then
    kubeconform "$@"
  else
    docker run -i ghcr.io/yannh/kubeconform:latest "$@"
  fi
}

# Map kubeconform status to display label
status_label() {
  case "$1" in
    statusValid)   echo "pass" ;;
    statusSkipped) echo "skip" ;;
    *)             echo "FAIL" ;;
  esac
}

# Validate chart against a single Kubernetes version.
# Produces kubeconform-{version}.json and kubeconform-report-{version}.md.
# Returns 0 on success, 1 on failure.
validate_version() {
  local version="$1"
  local json_file="kubeconform-${version}.json"
  local report_file="compatibility-matrix-${version}.md"

  echo "Validating against Kubernetes ${version}..."

  # Run kubeconform and save raw JSON
  helm template hello-distr "$CHART_DIR" --kube-version "$version" 2>/dev/null | \
    run_kubeconform \
      -kubernetes-version "$version" \
      -strict \
      -summary \
      -verbose \
      -output json \
      -schema-location default \
      -schema-location "$SCHEMA_LOCATION" \
    > "$json_file" || true

  local valid invalid errors skipped
  valid=$(jq '.summary.valid' "$json_file")
  invalid=$(jq '.summary.invalid' "$json_file")
  errors=$(jq '.summary.errors' "$json_file")
  skipped=$(jq '.summary.skipped' "$json_file")

  # Build per-version markdown report
  {
    echo "# Compatibility Matrix Test Report — Kubernetes ${version}"
    echo ""
    echo "**Date:** $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo ""
    echo "## Summary"
    echo ""
    echo "| Status | Count |"
    echo "|--------|-------|"
    echo "| Valid | ${valid} |"
    echo "| Invalid | ${invalid} |"
    echo "| Errors | ${errors} |"
    echo "| Skipped | ${skipped} |"
    echo ""
    echo "## Resources"
    echo ""
    echo "| Status | Kind | apiVersion | Name | Message |"
    echo "|--------|------|------------|------|---------|"

    # List every resource with its validation status
    jq -r '.resources[]? | "\(.status)\t\(.kind)\t\(.version)\t\(.name)\t\(.msg)"' "$json_file" | \
      while IFS=$'\t' read -r status kind apiversion name msg; do
        label=$(status_label "$status")
        echo "| ${label} | ${kind} | ${apiversion} | ${name} | ${msg} |"
      done

    echo ""

    if [ "$invalid" -gt 0 ] || [ "$errors" -gt 0 ]; then
      echo "---"
      echo ""
      echo "**Result: FAIL**"
    else
      echo "---"
      echo ""
      echo "**Result: PASS**"
    fi
    echo ""
    echo "---"
    echo ""
    echo "*Generated with [kubeconform](https://github.com/yannh/kubeconform)*"
  } > "$report_file"

  # Print summary to stdout
  if [ "$invalid" -gt 0 ] || [ "$errors" -gt 0 ]; then
    echo "  FAIL: ${valid} valid, ${invalid} invalid, ${errors} errors, ${skipped} skipped"
    return 1
  else
    echo "  PASS: ${valid} valid, ${skipped} skipped"
    return 0
  fi
}

# --- Main ---

helm dependency build "$CHART_DIR" 2>/dev/null

if [ $# -ge 1 ]; then
  # Single-version mode (CI)
  validate_version "$1"
else
  # All-versions mode (local)
  HAS_FAILURE=0

  for version in "${ALL_VERSIONS[@]}"; do
    validate_version "$version" || HAS_FAILURE=1
  done

  # Generate unified report
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  "$SCRIPT_DIR/distr-compatibility-matrix-merge-reports.sh" .

  echo ""
  if [ "$HAS_FAILURE" -eq 1 ]; then
    echo "Validation failed. See compatibility-matrix.md for details."
    exit 1
  else
    echo "All validations passed. Report written to compatibility-matrix.md"
  fi
fi
