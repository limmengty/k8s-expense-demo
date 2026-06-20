#!/usr/bin/env bash
# ============================================================
# pre-commit-check.sh — Run before every commit/PR
# Validates YAML syntax and kustomize build for all overlays
# Usage: ./scripts/pre-commit-check.sh
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ERRORS=0

echo "==> Checking YAML lint..."
if command -v yamllint &>/dev/null; then
  yamllint -d relaxed "$ROOT_DIR/apps" "$ROOT_DIR/infrastructure" "$ROOT_DIR/argocd" && \
    echo "  ✓ YAML lint passed" || { echo "  ✗ YAML lint failed"; ERRORS=$((ERRORS+1)); }
else
  echo "  ⚠ yamllint not installed — skipping (pip install yamllint)"
fi

echo ""
echo "==> Checking required tools..."
if ! command -v kustomize &>/dev/null; then
  echo "❌ kustomize not installed"
  echo "   Install: https://kubectl.docs.kubernetes.io/installation/kustomize/"
  echo "   Or: go install sigs.k8s.io/kustomize/kustomize/v5@latest"
  exit 1
fi
echo "  ✓ kustomize $(kustomize version --short 2>/dev/null || kustomize version)"

echo ""
echo "==> Validating kustomize builds..."
OVERLAYS=(
  "apps/expense-api/overlays/dev"
  "apps/expense-api/overlays/staging"
  "apps/expense-api/overlays/prod"
  "apps/expense-ui/overlays/dev"
  "apps/expense-ui/overlays/staging"
  "apps/expense-ui/overlays/prod"
)

for overlay in "${OVERLAYS[@]}"; do
  path="$ROOT_DIR/$overlay"
  if kustomize build "$path" > /dev/null 2>&1; then
    echo "  ✓ $overlay"
  else
    echo "  ✗ $overlay — kustomize build FAILED"
    kustomize build "$path" 2>&1 | head -20
    ERRORS=$((ERRORS+1))
  fi
done

echo ""
if [[ $ERRORS -eq 0 ]]; then
  echo "✅ All checks passed — safe to commit"
else
  echo "❌ $ERRORS check(s) failed — fix before committing"
  exit 1
fi
