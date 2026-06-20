#!/usr/bin/env bash
# ============================================================
# rollback.sh — Roll back an ArgoCD application to a previous revision
#
# Usage:
#   ./scripts/rollback.sh <app-name> [revision]
#
# Examples:
#   ./scripts/rollback.sh expense-api-prod          # roll back 1 revision
#   ./scripts/rollback.sh expense-api-prod 42       # roll back to revision 42
#   ./scripts/rollback.sh expense-ui-staging        # roll back staging UI
# ============================================================
set -euo pipefail

APP="${1:?Usage: $0 <app-name> [revision]}"
REVISION="${2:-}"

echo "==> Checking current status of $APP..."
argocd app get "$APP" --show-params

echo ""
if [[ -n "$REVISION" ]]; then
  echo "==> Rolling back $APP to revision $REVISION..."
  argocd app rollback "$APP" "$REVISION"
else
  echo "==> Rolling back $APP to previous revision..."
  argocd app rollback "$APP"
fi

echo ""
echo "==> Waiting for rollback to complete..."
argocd app wait "$APP" --sync --health --timeout 300

echo ""
echo "==> Post-rollback status:"
argocd app get "$APP"

echo ""
echo "✅ Rollback complete. Verify:"

# Derive namespace and component from app name (e.g. expense-api-prod → expense-api / prod)
COMPONENT="${APP%-*}"        # expense-api-prod → expense-api
ENV_SUFFIX="${APP##*-}"      # expense-api-prod → prod
NAMESPACE="${COMPONENT}-${ENV_SUFFIX}"  # expense-api-prod

echo "   kubectl get pods -n ${NAMESPACE} --field-selector=status.phase!=Running"
echo "   kubectl logs -l app.kubernetes.io/name=${COMPONENT} -n ${NAMESPACE} --tail=50"
echo "   curl -sf https://${ENV_SUFFIX}-${COMPONENT}.limmengty.com/actuator/health || echo 'health check failed'"
