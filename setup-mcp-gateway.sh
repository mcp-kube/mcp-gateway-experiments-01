#!/bin/bash
#
# Setup script for MCP Gateway on existing Kubernetes cluster
# This script installs MCP Gateway components on your current cluster
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check for kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed. Please install kubectl first."
        exit 1
    fi

    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
        exit 1
    fi

    # Show cluster info
    CLUSTER_INFO=$(kubectl cluster-info | head -1)
    log_info "Connected to: $CLUSTER_INFO"

    log_info "All prerequisites satisfied ✓"
}

# Install Gateway API CRDs
install_gateway_api() {
    log_info "Installing Gateway API CRDs..."

    # Check if already installed
    if kubectl get crd gateways.gateway.networking.k8s.io &> /dev/null; then
        log_warn "Gateway API CRDs already installed, skipping"
        return
    fi

    kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml

    log_info "Gateway API CRDs installed ✓"
}

# Install Envoy Gateway (Gateway API provider)
install_gateway_provider() {
    log_info "Checking for Gateway API provider..."

    # Check if Envoy Gateway is already installed
    if kubectl get namespace envoy-gateway-system &> /dev/null; then
        log_info "Envoy Gateway already installed ✓"
        return
    fi

    # Check if Istio is installed
    if kubectl get namespace istio-system &> /dev/null; then
        log_info "Istio detected, using it as Gateway API provider ✓"
        return
    fi

    log_info "Installing Envoy Gateway (lightweight Gateway API provider)..."

    # Install Envoy Gateway using server-side apply to avoid annotation size limits
    kubectl apply --server-side -f https://github.com/envoyproxy/gateway/releases/download/v1.2.4/install.yaml

    # Wait for Envoy Gateway to be ready
    log_info "Waiting for Envoy Gateway to be ready..."
    kubectl wait --for=condition=available deployment/envoy-gateway -n envoy-gateway-system --timeout=120s

    # Create GatewayClass
    log_info "Creating Envoy Gateway GatewayClass..."
    cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
EOF

    log_info "Envoy Gateway installed ✓"
}

# Install MCP Gateway components
install_mcp_gateway() {
    log_info "Installing MCP Gateway components..."

    cd mcp-gateway || exit 1

    # Use kustomize to install
    kubectl apply -k config/install

    cd ..

    log_info "MCP Gateway components installed ✓"
}

# Update image references to use local/pushed images
update_images() {
    log_info "Updating deployment images..."

    local DOCKER_USERNAME="${DOCKER_USERNAME:-aliok}"
    local IMAGE_TAG="${IMAGE_TAG:-latest}"

    log_info "Using images: $DOCKER_USERNAME/mcp-gateway:$IMAGE_TAG and $DOCKER_USERNAME/mcp-controller:$IMAGE_TAG"

    # Update broker-router image
    kubectl set image deployment/mcp-broker-router \
        mcp-broker-router=$DOCKER_USERNAME/mcp-gateway:$IMAGE_TAG \
        -n mcp-system

    # Update controller image
    kubectl set image deployment/mcp-controller \
        mcp-controller=$DOCKER_USERNAME/mcp-controller:$IMAGE_TAG \
        -n mcp-system

    log_info "Deployment images updated ✓"
}

# Create Gateway resource
create_gateway() {
    log_info "Creating Gateway resource..."

    # Check if gateway already exists
    if kubectl get gateway mcp-gateway -n mcp-system &> /dev/null 2>&1; then
        log_warn "Gateway already exists, skipping"
        return
    fi

    # Determine gateway class based on installed provider
    local GATEWAY_CLASS="eg"  # Default to Envoy Gateway
    if kubectl get namespace istio-system &> /dev/null; then
        GATEWAY_CLASS="istio"
    fi

    log_info "Using gateway class: $GATEWAY_CLASS"

    # Create gateway
    cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: mcp-gateway
  namespace: mcp-system
spec:
  gatewayClassName: $GATEWAY_CLASS
  listeners:
  - name: http
    protocol: HTTP
    port: 8080
    allowedRoutes:
      namespaces:
        from: All
EOF

    log_info "Gateway resource created ✓"
}

# Verify installation
verify_installation() {
    log_info "Verifying MCP Gateway installation..."

    # Wait for namespace
    log_info "Waiting for mcp-system namespace..."
    kubectl wait --for=jsonpath='{.status.phase}'=Active namespace/mcp-system --timeout=60s 2>/dev/null || true

    # Wait for deployments
    log_info "Waiting for deployments to be ready (this may take a minute)..."

    kubectl wait --for=condition=available deployment/mcp-controller \
        -n mcp-system \
        --timeout=120s 2>/dev/null || log_warn "Controller not ready yet"

    kubectl wait --for=condition=available deployment/mcp-broker-router \
        -n mcp-system \
        --timeout=120s 2>/dev/null || log_warn "Broker-router not ready yet"

    # Show status
    echo ""
    log_info "MCP Gateway pods:"
    kubectl get pods -n mcp-system

    echo ""
    log_info "MCP Gateway services:"
    kubectl get services -n mcp-system

    echo ""
    log_info "Gateway resources:"
    kubectl get gateway -n mcp-system

    echo ""
    log_info "MCP Gateway is ready ✓"
}

# Display next steps
show_next_steps() {
    echo ""
    log_info "=========================================="
    log_info "MCP Gateway Setup Complete!"
    log_info "=========================================="
    echo ""
    echo "Next steps:"
    echo "  1. Deploy MCP servers using:"
    echo "     ./deploy-mcp-servers.sh"
    echo ""
    echo "  2. Check MCPServerRegistration resources:"
    echo "     kubectl get mcpserverregistrations -A"
    echo ""
    echo "  3. View broker logs:"
    echo "     kubectl logs -n mcp-system deployment/mcp-broker-router -f"
    echo ""
    echo "  4. Port forward to access the gateway:"
    echo "     kubectl port-forward -n mcp-system svc/mcp-broker 8080:8080"
    echo "     # Then access at http://localhost:8080/mcp"
    echo ""
}

# Main execution
main() {
    log_info "=========================================="
    log_info "MCP Gateway Setup"
    log_info "=========================================="
    echo ""

    check_prerequisites
    install_gateway_api
    install_gateway_provider
    install_mcp_gateway
    update_images
    create_gateway
    verify_installation
    show_next_steps
}

# Run main function with all arguments
main "$@"
