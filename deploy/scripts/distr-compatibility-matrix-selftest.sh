#!/usr/bin/env bash
set -euo pipefail

# Self-tests for kubeconform validation.
# Verifies that kubeconform correctly detects version-specific resources.

run_kubeconform() {
  if command -v kubeconform &>/dev/null; then
    kubeconform "$@"
  else
    docker run -i ghcr.io/yannh/kubeconform:latest "$@"
  fi
}

WORKLOAD_MANIFEST=$(cat <<'MANIFEST'
apiVersion: scheduling.k8s.io/v1alpha1
kind: Workload
metadata:
  name: kubeconform-selftest
spec:
  controllerRef:
    apiGroup: batch
    kind: Job
    name: selftest-job
  podGroups:
    - name: workers
      policy:
        gang:
          minCount: 1
MANIFEST
)

echo "Running kubeconform self-tests..."

# Test 1: Workload resource (introduced in K8s 1.35) must error on 1.34
RESULT=$(echo "$WORKLOAD_MANIFEST" | run_kubeconform -kubernetes-version 1.34.0 -summary -output json -schema-location default 2>&1) || true
if ! echo "$RESULT" | jq empty 2>/dev/null; then
  echo "FAIL: kubeconform did not produce valid JSON output"
  echo "$RESULT"
  exit 1
fi
ERRORS=$(echo "$RESULT" | jq '.summary.errors')
if [ "$ERRORS" -lt 1 ]; then
  echo "FAIL: Workload should error on Kubernetes 1.34 but got errors=$ERRORS"
  exit 1
fi
echo "  PASS: Workload correctly rejected on Kubernetes 1.34"

# Test 2: Workload resource must pass on 1.35
RESULT=$(echo "$WORKLOAD_MANIFEST" | run_kubeconform -kubernetes-version 1.35.0 -summary -output json -schema-location default 2>&1) || true
if ! echo "$RESULT" | jq empty 2>/dev/null; then
  echo "FAIL: kubeconform did not produce valid JSON output"
  echo "$RESULT"
  exit 1
fi
VALID=$(echo "$RESULT" | jq '.summary.valid')
if [ "$VALID" -lt 1 ]; then
  echo "FAIL: Workload should be valid on Kubernetes 1.35 but got valid=$VALID"
  exit 1
fi
echo "  PASS: Workload correctly accepted on Kubernetes 1.35"

echo "All self-tests passed."
