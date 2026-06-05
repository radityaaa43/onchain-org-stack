#!/usr/bin/env bash
set -euo pipefail

ARGOCD_VERSION="v2.13.3"
NAMESPACE="argocd"

kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -n "${NAMESPACE}" \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

echo "Waiting for argocd-server deployment to be available (timeout 300s)..."
kubectl rollout status deployment/argocd-server -n "${NAMESPACE}" --timeout=300s

echo ""
echo "ArgoCD installed. Retrieve initial admin password with:"
echo "  kubectl -n ${NAMESPACE} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo"
