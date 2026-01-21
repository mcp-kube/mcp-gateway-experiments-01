#!/bin/bash
set -e

# Cleanup script for MCP Gateway
# Removes MCP Gateway deployment from Kubernetes cluster

# Configuration
NAMESPACE="${NAMESPACE:-mcp-system}"

echo "========================================="
echo "MCP Gateway Cleanup"
echo "========================================="
echo "Namespace: $NAMESPACE"
echo ""
echo "WARNING: This will delete all MCP Gateway resources"
echo "========================================="

# Prompt for confirmation
read -p "Are you sure you want to continue? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "Cleanup cancelled"
  exit 0
fi

echo ""
echo "[1/5] Deleting MCP Gateway deployments..."
kubectl delete deployment mcp-broker-router -n $NAMESPACE --ignore-not-found=true
kubectl delete deployment mcp-controller -n $NAMESPACE --ignore-not-found=true
echo "  ✓ Deployments deleted"

echo ""
echo "[2/5] Deleting services..."
kubectl delete service mcp-broker -n $NAMESPACE --ignore-not-found=true
echo "  ✓ Services deleted"

echo ""
echo "[3/5] Deleting HTTPRoutes..."
kubectl delete httproute mcp-route -n $NAMESPACE --ignore-not-found=true
echo "  ✓ HTTPRoutes deleted"

echo ""
echo "[4/5] Deleting RBAC resources..."
kubectl delete serviceaccount mcp-broker-router -n $NAMESPACE --ignore-not-found=true
kubectl delete serviceaccount mcp-controller -n $NAMESPACE --ignore-not-found=true
kubectl delete rolebinding mcp-broker-router -n $NAMESPACE --ignore-not-found=true
kubectl delete clusterrolebinding mcp-controller --ignore-not-found=true
kubectl delete role mcp-broker-router -n $NAMESPACE --ignore-not-found=true
kubectl delete clusterrole mcp-controller --ignore-not-found=true
echo "  ✓ RBAC resources deleted"

echo ""
echo "[5/5] Deleting secrets and namespace..."
kubectl delete secret mcp-gateway-config -n $NAMESPACE --ignore-not-found=true
kubectl delete secret trusted-headers-public-key -n $NAMESPACE --ignore-not-found=true

# Ask about namespace deletion
read -p "Delete namespace '$NAMESPACE'? (yes/no): " DELETE_NS
if [ "$DELETE_NS" = "yes" ]; then
  kubectl delete namespace $NAMESPACE --ignore-not-found=true
  echo "  ✓ Namespace deleted"
else
  echo "  ⊘ Namespace preserved"
fi

echo ""
echo "========================================="
echo "Cleanup options:"
echo "========================================="
read -p "Delete MCP Gateway CRDs? (yes/no): " DELETE_CRDS
if [ "$DELETE_CRDS" = "yes" ]; then
  echo "  Deleting CRDs..."
  kubectl delete crd mcpgatewayextensions.mcp.kagenti.com --ignore-not-found=true
  kubectl delete crd mcpserverregistrations.mcp.kagenti.com --ignore-not-found=true
  kubectl delete crd mcpvirtualservers.mcp.kagenti.com --ignore-not-found=true
  echo "  ✓ CRDs deleted"
else
  echo "  ⊘ CRDs preserved"
fi

read -p "Delete Gateway API CRDs? (yes/no): " DELETE_GATEWAY_API
if [ "$DELETE_GATEWAY_API" = "yes" ]; then
  echo "  Deleting Gateway API CRDs..."
  kubectl delete crd gatewayclasses.gateway.networking.k8s.io --ignore-not-found=true
  kubectl delete crd gateways.gateway.networking.k8s.io --ignore-not-found=true
  kubectl delete crd grpcroutes.gateway.networking.k8s.io --ignore-not-found=true
  kubectl delete crd httproutes.gateway.networking.k8s.io --ignore-not-found=true
  kubectl delete crd referencegrants.gateway.networking.k8s.io --ignore-not-found=true
  echo "  ✓ Gateway API CRDs deleted"
else
  echo "  ⊘ Gateway API CRDs preserved"
fi

echo ""
echo "========================================="
echo "Cleanup Complete!"
echo "========================================="
echo ""
echo "Remaining resources:"
kubectl get all -n $NAMESPACE 2>/dev/null || echo "  (namespace deleted)"

echo ""
echo "To redeploy:"
echo "  ./scripts/deploy.sh"
echo "========================================="