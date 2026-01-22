#!/bin/bash
#
# Setup script for MCP Gateway with Istio on existing Kubernetes cluster
# This script uses the MCP Gateway's Makefile targets for installation
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
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

    # Check for mcp-gateway directory
    if [ ! -d "mcp-gateway" ]; then
        log_error "mcp-gateway directory not found. Please run from repository root."
        exit 1
    fi

    log_info "All prerequisites satisfied ✓"
}

# Install required tools
install_tools() {
    log_step "Installing required tools..."

    cd mcp-gateway
    make tools
    cd ..

    log_info "Tools installed ✓"
}

# Install Gateway API CRDs
install_gateway_api() {
    log_step "Installing Gateway API CRDs..."

    cd mcp-gateway
    make gateway-api-install
    cd ..

    log_info "Gateway API CRDs installed ✓"
}

# Install Istio using Sail operator
install_istio() {
    log_step "Installing Istio using Sail operator..."

    # Check if Istio is already installed
    if kubectl get namespace istio-system &> /dev/null 2>&1; then
        log_warn "Istio namespace already exists, skipping installation"
        return
    fi

    cd mcp-gateway
    make istio-install
    cd ..

    log_info "Istio installed ✓"
}

# Deploy namespaces
deploy_namespaces() {
    log_step "Creating MCP namespaces..."

    cd mcp-gateway
    make deploy-namespaces
    cd ..

    log_info "Namespaces created ✓"
}

# Deploy Istio Gateway
deploy_gateway() {
    log_step "Deploying Istio Gateway..."

    cd mcp-gateway
    make deploy-gateway
    cd ..

    log_info "Gateway deployed ✓"
}

# Deploy MCP Gateway components
deploy_mcp_gateway() {
    log_step "Deploying MCP Gateway components (broker, router, controller)..."

    cd mcp-gateway
    make deploy
    cd ..

    log_info "MCP Gateway components deployed ✓"
}

# Update image references to use custom images
update_images() {
    local DOCKER_USERNAME="${DOCKER_USERNAME:-aliok}"
    local IMAGE_TAG="${IMAGE_TAG:-latest}"

    log_step "Checking if custom images should be used..."
    log_info "Using images: $DOCKER_USERNAME/mcp-gateway:$IMAGE_TAG and $DOCKER_USERNAME/mcp-controller:$IMAGE_TAG"

    # Check if images need updating (only if using custom images)
    if [ "$DOCKER_USERNAME" != "ghcr.io/kagenti" ]; then
        log_info "Updating deployment images..."

        # Wait for deployments to exist
        kubectl wait --for=condition=available deployment/mcp-broker-router -n mcp-system --timeout=60s 2>/dev/null || true
        kubectl wait --for=condition=available deployment/mcp-controller -n mcp-system --timeout=60s 2>/dev/null || true

        # Update broker-router image
        kubectl set image deployment/mcp-broker-router \
            mcp-broker-router=$DOCKER_USERNAME/mcp-gateway:$IMAGE_TAG \
            -n mcp-system || log_warn "Failed to update broker-router image"

        # Update controller image
        kubectl set image deployment/mcp-controller \
            mcp-controller=$DOCKER_USERNAME/mcp-controller:$IMAGE_TAG \
            -n mcp-system || log_warn "Failed to update controller image"

        log_info "Deployment images updated ✓"
    else
        log_info "Using default images ✓"
    fi
}

# Verify installation
verify_installation() {
    log_step "Verifying MCP Gateway installation..."

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
    log_info "Istio system pods:"
    kubectl get pods -n istio-system

    echo ""
    log_info "Gateway system pods:"
    kubectl get pods -n gateway-system

    echo ""
    log_info "MCP Gateway pods:"
    kubectl get pods -n mcp-system

    echo ""
    log_info "MCP Gateway services:"
    kubectl get services -n mcp-system

    echo ""
    log_info "Gateway resources:"
    kubectl get gateway -n gateway-system

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
    echo "  4. Port forward to access the gateway (for tool execution):"
    echo "     kubectl port-forward -n gateway-system svc/mcp-gateway-istio 8080:8080"
    echo "     # Then access at http://mcp.127-0-0-1.sslip.io:8080/mcp"
    echo "     # Note: Must use hostname 'mcp.127-0-0-1.sslip.io', not 'localhost'"
    echo ""
    echo "  5. Test the gateway:"
    echo "     ./test-servers.sh"
    echo ""
}

# Main execution
main() {
    log_info "=========================================="
    log_info "MCP Gateway Setup with Istio"
    log_info "=========================================="
    echo ""

    check_prerequisites
    install_tools
    install_gateway_api
    install_istio
    deploy_namespaces
    deploy_gateway
    deploy_mcp_gateway
    update_images
    verify_installation
    show_next_steps
}

# Run main function with all arguments
main "$@"
