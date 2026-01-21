#!/bin/bash
#
# Cleanup script for MCP Gateway experiments
# This script removes MCP servers and optionally the entire Kind cluster
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

# Parse command line arguments
CLEANUP_CLUSTER=false
if [ "$1" = "--cluster" ]; then
    CLEANUP_CLUSTER=true
fi

# Main cleanup
main() {
    log_info "=========================================="
    log_info "MCP Gateway Experiments Cleanup"
    log_info "=========================================="
    echo ""

    if [ "$CLEANUP_CLUSTER" = true ]; then
        log_warn "This will delete the entire Kind cluster!"
        read -p "Are you sure? (yes/no): " CONFIRM
        if [ "$CONFIRM" != "yes" ]; then
            log_info "Cleanup cancelled"
            exit 0
        fi

        log_info "Tearing down Kind cluster..."
        cd mcp-gateway || exit 1
        make local-env-teardown
        cd ..

        log_info "Kind cluster deleted ✓"
    else
        log_info "Cleaning up MCP servers and registrations..."
        echo ""

        # Delete MCPServerRegistration resources
        log_info "Deleting MCPServerRegistration resources..."
        kubectl delete -f sample-servers/mcpserverregistration-sse.yaml --ignore-not-found=true
        kubectl delete -f sample-servers/mcpserverregistration-streamable-http.yaml --ignore-not-found=true
        log_info "MCPServerRegistrations deleted ✓"

        echo ""
        log_info "Deleting test server deployments..."
        kubectl delete namespace mcp-test --ignore-not-found=true 2>/dev/null || true
        log_info "Test servers deleted ✓"

        echo ""
        log_info "MCP servers cleaned up ✓"
        echo ""
        log_info "To clean up the entire cluster, run:"
        log_info "  ./cleanup.sh --cluster"
    fi

    echo ""
    log_info "=========================================="
    log_info "Cleanup Complete!"
    log_info "=========================================="
}

# Run main function
main "$@"
