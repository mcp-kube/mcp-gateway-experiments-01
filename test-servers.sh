#!/bin/bash
#
# Test script for deployed MCP servers
# This script tests connectivity and functionality of the deployed MCP servers
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

log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

# Test gateway endpoint
test_gateway_broker() {
    log_test "Testing MCP Gateway broker endpoint..."

    # Port forward in background
    kubectl port-forward -n mcp-system svc/mcp-broker 8080:8080 &
    PF_PID=$!

    # Wait for port forward to establish
    sleep 3

    # Test broker status endpoint
    if curl -sf "http://localhost:8080/status" > /dev/null; then
        log_info "Gateway broker status check passed ✓"

        # Show registered servers
        echo ""
        log_info "Registered servers:"
        curl -sf "http://localhost:8080/status" | jq -r '.servers[] | "  - \(.name): \(.url) (\(.toolCount) tools)"' 2>/dev/null || true
    else
        log_error "Gateway broker status check failed ✗"
    fi

    # Kill port forward
    kill $PF_PID 2>/dev/null || true
    wait $PF_PID 2>/dev/null || true

    sleep 2
}

# Test MCP endpoint with tools/list
test_tools_list() {
    log_test "Testing tools/list endpoint..."

    kubectl port-forward -n mcp-system svc/mcp-broker 8080:8080 &
    PF_PID=$!

    sleep 3

    # Test MCP tools/list endpoint
    RESPONSE=$(curl -sf "http://localhost:8080/mcp" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' \
        --max-time 10 2>/dev/null || echo "failed")

    if [ "$RESPONSE" != "failed" ]; then
        log_info "tools/list endpoint responded ✓"

        # Show available tools
        echo ""
        log_info "Available tools:"
        echo "$RESPONSE" | jq -r '.result.tools[] | "  - \(.name): \(.description)"' 2>/dev/null || echo "$RESPONSE" | head -n 5
    else
        log_warn "tools/list endpoint test failed"
    fi

    kill $PF_PID 2>/dev/null || true
    wait $PF_PID 2>/dev/null || true

    sleep 2
}

# Test individual server
test_individual_server() {
    local SERVER_NAME=$1
    local NAMESPACE=$2
    local PORT=$3

    log_test "Testing individual server: $SERVER_NAME..."

    # Check if service exists
    if ! kubectl get service "$SERVER_NAME" -n "$NAMESPACE" &> /dev/null; then
        log_warn "Service $SERVER_NAME not found in namespace $NAMESPACE"
        return
    fi

    kubectl port-forward "service/$SERVER_NAME" -n "$NAMESPACE" "$PORT:$PORT" &
    PF_PID=$!

    sleep 3

    # Test MCP endpoint
    RESPONSE=$(curl -sf "http://localhost:$PORT/mcp" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' \
        --max-time 5 2>/dev/null || echo "failed")

    if [ "$RESPONSE" != "failed" ]; then
        log_info "$SERVER_NAME responded ✓"
    else
        log_warn "$SERVER_NAME test inconclusive"
    fi

    kill $PF_PID 2>/dev/null || true
    wait $PF_PID 2>/dev/null || true

    sleep 2
}

# Show pod status
show_pod_status() {
    log_info "=========================================="
    log_info "Pod Status"
    log_info "=========================================="
    echo ""

    log_info "MCP Gateway pods:"
    kubectl get pods -n mcp-system

    echo ""
    log_info "MCP test server pods:"
    kubectl get pods -n mcp-test 2>/dev/null || log_warn "mcp-test namespace not found"

    echo ""
}

# Show MCPServerRegistration status
show_mcpserver_status() {
    log_info "=========================================="
    log_info "MCPServerRegistration Resources"
    log_info "=========================================="
    echo ""

    kubectl get mcpserverregistrations -n mcp-test 2>/dev/null || log_warn "No MCPServerRegistrations found"

    echo ""
}

# Show HTTPRoute status
show_httproute_status() {
    log_info "=========================================="
    log_info "HTTPRoute Resources"
    log_info "=========================================="
    echo ""

    kubectl get httproutes -n mcp-test 2>/dev/null || log_warn "No HTTPRoutes found"

    echo ""
}

# Main execution
main() {
    log_info "=========================================="
    log_info "Testing MCP Servers"
    log_info "=========================================="
    echo ""

    show_mcpserver_status
    show_httproute_status
    show_pod_status

    log_info "Running connectivity tests..."
    echo ""

    test_gateway_broker
    test_tools_list

    # Test individual servers if they exist
    test_individual_server "mcp-server-streamable-http" "mcp-test" 8081

    echo ""
    log_info "=========================================="
    log_info "Test Summary"
    log_info "=========================================="
    echo ""
    echo "For interactive testing with MCP Inspector:"
    echo ""
    echo "1. Test the gateway (aggregated tools):"
    echo "   cd mcp-gateway && make inspect-gateway"
    echo ""
    echo "2. Or manually:"
    echo "   npx @modelcontextprotocol/inspector http://mcp.127-0-0-1.sslip.io:8001/mcp"
    echo ""
    echo "3. Check broker status:"
    echo "   kubectl port-forward -n mcp-system svc/mcp-broker 8080:8080"
    echo "   curl http://localhost:8080/status | jq"
    echo ""
    echo "4. View logs:"
    echo "   kubectl logs -n mcp-system deployment/mcp-broker-router -f"
    echo "   kubectl logs -n mcp-system deployment/mcp-controller -f"
    echo ""
}

# Run main function
main "$@"