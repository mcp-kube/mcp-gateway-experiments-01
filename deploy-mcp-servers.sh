#!/bin/bash
# Deployment script for MCP servers using MCP Gateway
# This script deploys sample MCP servers and registers them with the gateway
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

# Check if MCP Gateway is installed
check_mcp_gateway() {
    log_info "Checking MCP Gateway installation..."

    if ! kubectl get namespace mcp-system &> /dev/null; then
        log_error "mcp-system namespace not found. Please run ./setup-mcp-gateway.sh first."
        exit 1
    fi

    if ! kubectl get deployment mcp-broker-router -n mcp-system &> /dev/null; then
        log_error "MCP Gateway not found. Please run ./setup-mcp-gateway.sh first."
        exit 1
    fi

    log_info "MCP Gateway is installed ✓"
}

# Deploy sample MCP servers
deploy_sample_servers() {
    log_step "Deploying sample MCP servers..."
    echo ""

    # Create namespace
    log_info "Creating mcp-test namespace..."
    kubectl create namespace mcp-test --dry-run=client -o yaml | kubectl apply -f -

    # Deploy SSE server
    log_info "Deploying SSE server..."
    kubectl apply -f sample-servers/sse-server-deployment.yaml

    # Deploy Streamable HTTP server
    log_info "Deploying Streamable HTTP server..."
    kubectl apply -f sample-servers/streamable-http-server-deployment.yaml

    log_info "Sample MCP server deployments created ✓"
}

# Deploy MCPServerRegistration resources
deploy_registrations() {
    log_step "Deploying MCPServerRegistration resources..."
    echo ""

    log_info "Applying MCPServerRegistration for SSE server..."
    kubectl apply -f sample-servers/mcpserverregistration-sse.yaml

    log_info "Applying MCPServerRegistration for Streamable HTTP server..."
    kubectl apply -f sample-servers/mcpserverregistration-streamable-http.yaml

    echo ""
    log_info "MCPServerRegistration resources deployed ✓"
}

# Wait for servers to be ready
wait_for_servers() {
    log_step "Waiting for MCP servers to be ready..."
    echo ""

    log_info "Waiting for MCP server pods to start..."
    sleep 5

    # Show deployment status
    log_info "MCP test namespace pods:"
    kubectl get pods -n mcp-test 2>/dev/null || log_warn "mcp-test namespace not created yet"

    echo ""
    log_info "Waiting for server deployments to be ready (this may take a minute)..."
    kubectl wait --for=condition=available deployment/mcp-server-sse -n mcp-test --timeout=120s 2>/dev/null || log_warn "SSE server not ready yet"
    kubectl wait --for=condition=available deployment/mcp-server-streamable-http -n mcp-test --timeout=120s 2>/dev/null || log_warn "Streamable HTTP server not ready yet"

    echo ""
    log_info "MCPServerRegistration resources:"
    kubectl get mcpserverregistrations -n mcp-test 2>/dev/null || log_warn "No MCPServerRegistrations found yet"

    echo ""
    log_info "Note: The controller will discover servers via HTTPRoutes."
    log_info "You can monitor the progress with:"
    echo "  kubectl get mcpserverregistrations -n mcp-test -w"
}

# Show service information
show_services() {
    log_step "Checking deployed services..."
    echo ""

    log_info "Services in mcp-test namespace:"
    kubectl get services -n mcp-test 2>/dev/null || log_warn "No services found yet"

    echo ""
    log_info "HTTPRoutes:"
    kubectl get httproutes -n mcp-test 2>/dev/null || log_warn "No HTTPRoutes found yet"

    echo ""
    log_info "Deployments:"
    kubectl get deployments -n mcp-test 2>/dev/null || log_warn "No deployments found yet"
}

# Show access instructions
show_access_instructions() {
    echo ""
    log_step "=========================================="
    log_step "MCP Servers Deployed Successfully!"
    log_step "=========================================="
    echo ""

    echo "The MCP Gateway is now aggregating tools from your sample servers."
    echo ""
    echo "Deployed servers:"
    echo "  - SSE server (tools: calculate, generate_uuid, reverse_string)"
    echo "  - Streamable HTTP server (tools: base64_encode, sha256_hash, get_timestamp, json_validate, url_encode)"
    echo ""
    echo "Access the gateway:"
    echo "  kubectl port-forward -n mcp-system svc/mcp-broker 8080:8080"
    echo "  # Then access at http://localhost:8080/mcp"
    echo ""
    echo "List all tools:"
    echo "  curl http://localhost:8080/mcp \\\\"
    echo "    -H 'Content-Type: application/json' \\\\"
    echo "    -d '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\",\"params\":{}}'"
    echo ""
    echo "View broker status:"
    echo "  curl http://localhost:8080/status | jq"
    echo ""
    echo "Check MCPServerRegistration status:"
    echo "  kubectl describe mcpserverregistration sse-server -n mcp-test"
    echo ""
    echo "View logs:"
    echo "  kubectl logs -n mcp-system deployment/mcp-broker-router -f"
    echo "  kubectl logs -n mcp-system deployment/mcp-controller -f"
    echo ""
    echo "To test servers:"
    echo "  ./test-servers.sh"
    echo ""
    echo "To clean up:"
    echo "  ./cleanup.sh"
    echo ""
}

# Main execution
main() {
    log_info "=========================================="
    log_info "MCP Servers Deployment"
    log_info "=========================================="
    echo ""

    check_mcp_gateway
    deploy_sample_servers
    deploy_registrations
    wait_for_servers
    show_services
    show_access_instructions
}

# Run main function
main "$@"
