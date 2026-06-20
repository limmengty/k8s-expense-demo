#!/usr/bin/env bash
# ============================================================
# deploy.sh — CI→CD handoff script
# Updates the image tag in a kustomize overlay and commits.
# Run from CI after building a new Docker image.
#
# Usage:
#   ./scripts/deploy.sh <component> <overlay> <image-tag>
#
# Examples:
#   ./scripts/deploy.sh expense-api dev abc1234
#   ./scripts/deploy.sh expense-ui staging def5678
# ============================================================
set -euo pipefail

COMPONENT="${1:?Usage: $0 <component> <overlay> <image-tag>}"
OVERLAY="${2:?Usage: $0 <component> <overlay> <image-tag>}"
IMAGE_TAG="${3:?Usage: $0 <component> <overlay> <image-tag>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
OVERLAY_DIR="$ROOT_DIR/apps/$COMPONENT/overlays/$OVERLAY"

if [[ ! -d "$OVERLAY_DIR" ]]; then
  echo "❌ Overlay not found: $OVERLAY_DIR"
  exit 1
fi

echo "==> Updating $COMPONENT image to mengty199/$COMPONENT:$IMAGE_TAG in $OVERLAY..."
cd "$OVERLAY_DIR"
kustomize edit set image "mengty199/$COMPONENT=mengty199/$COMPONENT:$IMAGE_TAG"

echo "==> Committing..."
cd "$ROOT_DIR"
git add "apps/$COMPONENT/overlays/$OVERLAY/kustomization.yaml"
git commit -m "ci($COMPONENT): update image → $IMAGE_TAG [$OVERLAY]"
git push

echo "✅ Done. ArgoCD will sync automatically for dev/staging."
echo "   For prod: argocd app sync ${COMPONENT}-prod (manual)"
