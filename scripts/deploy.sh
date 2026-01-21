#!/bin/bash
set -e

# Deploy script for MCP Gateway
# Deploys MCP Gateway to Kubernetes cluster with custom images

# Configuration
DOCKER_USERNAME="${DOCKER_USERNAME:-aliok}"
IMAGE_TAG="${IMAGE_TAG:-v1}"
NAMESPACE="${NAMESPACE:-mcp-system}"

echo "========================================="
echo "Deploying MCP Gateway"
echo "========================================="
echo "Namespace: $NAMESPACE"
echo "Images:"
echo "  - $DOCKER_USERNAME/mcp-gateway:$IMAGE_TAG"
echo "  - $DOCKER_USERNAME/mcp-controller:$IMAGE_TAG"
echo "========================================="

# Check kubectl connectivity
echo ""
echo "[1/5] Checking Kubernetes cluster connectivity..."
if ! kubectl cluster-info > /dev/null 2>&1; then
  echo "Error: Cannot connect to Kubernetes cluster"
  echo "Please ensure kubectl is configured correctly"
  exit 1
fi
kubectl cluster-info | head -2
echo "  ✓ Cluster accessible"

# Check if Gateway API is installed
echo ""
echo "[2/5] Checking Gateway API installation..."
if ! kubectl get crd gateways.gateway.networking.k8s.io > /dev/null 2>&1; then
  echo "  Gateway API not found. Installing..."
  kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml
  echo "  ✓ Gateway API installed"
else
  echo "  ✓ Gateway API already installed"
fi

# Install MCP Gateway base manifests
echo ""
echo "[3/5] Installing MCP Gateway base manifests..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MCP_GATEWAY_DIR="$PROJECT_ROOT/mcp-gateway"

# Check if CRDs already exist (indicates previous installation)
if kubectl get crd mcpserverregistrations.mcp.kagenti.com > /dev/null 2>&1; then
  echo "  MCP Gateway CRDs already installed, skipping base install..."
  echo "  (Resources are already present from previous installation)"
else
  echo "  Installing from local repository..."
  if [ -d "$MCP_GATEWAY_DIR/config/install" ]; then
    kubectl apply -k "$MCP_GATEWAY_DIR/config/install"
  else
    echo "  Warning: Local mcp-gateway directory not found"
    echo "  Attempting to install from remote URL..."
    kubectl apply -k 'https://github.com/Kuadrant/mcp-gateway/config/install?ref=main'
  fi
fi
echo "  ✓ Base manifests applied"

# Wait for initial deployment
echo ""
echo "[4/5] Waiting for deployments to be created..."
sleep 5

# Update deployment images to use custom builds
echo ""
echo "[5/5] Updating deployments to use custom images..."

# Check current images
CURRENT_BROKER_IMAGE=$(kubectl get deployment mcp-broker-router -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "")
CURRENT_CONTROLLER_IMAGE=$(kubectl get deployment mcp-controller -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "")

DESIRED_BROKER_IMAGE="$DOCKER_USERNAME/mcp-gateway:$IMAGE_TAG"
DESIRED_CONTROLLER_IMAGE="$DOCKER_USERNAME/mcp-controller:$IMAGE_TAG"

# Update broker-router if needed
if [ "$CURRENT_BROKER_IMAGE" != "$DESIRED_BROKER_IMAGE" ]; then
  echo "  - Updating mcp-broker-router image: $CURRENT_BROKER_IMAGE → $DESIRED_BROKER_IMAGE"
  kubectl set image deployment/mcp-broker-router \
    mcp-broker-router=$DESIRED_BROKER_IMAGE \
    -n $NAMESPACE
else
  echo "  - mcp-broker-router already using: $DESIRED_BROKER_IMAGE"
fi

# Update controller if needed
if [ "$CURRENT_CONTROLLER_IMAGE" != "$DESIRED_CONTROLLER_IMAGE" ]; then
  echo "  - Updating mcp-controller image: $CURRENT_CONTROLLER_IMAGE → $DESIRED_CONTROLLER_IMAGE"
  kubectl set image deployment/mcp-controller \
    mcp-controller=$DESIRED_CONTROLLER_IMAGE \
    -n $NAMESPACE
else
  echo "  - mcp-controller already using: $DESIRED_CONTROLLER_IMAGE"
fi

echo ""
echo "  Waiting for deployments to be ready..."
kubectl rollout status deployment/mcp-controller -n $NAMESPACE --timeout=120s
kubectl rollout status deployment/mcp-broker-router -n $NAMESPACE --timeout=120s

echo ""
echo "========================================="
echo "Deployment Complete!"
echo "========================================="
echo ""
echo "Resources in namespace '$NAMESPACE':"
kubectl get all -n $NAMESPACE

echo ""
echo "========================================="
echo "Verification:"
echo "========================================="
echo ""
echo "Check pod logs:"
echo "  kubectl logs -n $NAMESPACE deployment/mcp-controller"
echo "  kubectl logs -n $NAMESPACE deployment/mcp-broker-router"
echo ""
echo "Check configuration:"
echo "  kubectl get secret mcp-gateway-config -n $NAMESPACE -o yaml"
echo ""
echo "Next steps:"
echo "  - Deploy test MCP servers"
echo "  - Create MCPServerRegistration resources"
echo "  - Configure HTTPRoutes"
echo "========================================="