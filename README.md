# MCP Gateway Kubernetes Experiments

Deploy and manage MCP (Model Context Protocol) servers on Kubernetes using the [MCP Gateway](https://github.com/Kuadrant/mcp-gateway).

**Note**: Experimental setup for learning and testing MCP Gateway capabilities.

## Quick Start

### Prerequisites

- kubectl connected to a Kubernetes cluster
- Docker (only needed if building custom images)

### Setup

```bash
# 1. Install MCP Gateway (uses pre-built images from Docker Hub)
./setup-mcp-gateway.sh

# 2. Deploy test MCP servers
./deploy-mcp-servers.sh

# 3. Verify deployment
./test-servers.sh
```

**Note**: The setup uses pre-built images from Docker Hub (`aliok/mcp-gateway:latest`, `aliok/mcp-controller:latest`). To build custom images, see the [Building Custom Images](#building-custom-images) section.

## What's Included

**Sample MCP servers:**

1. **Server 1** (Go SDK, Streamable HTTP) - Tools: calculate, generate_uuid, reverse_string - Prefix: `sse_`
2. **Server 2** (Go SDK, Streamable HTTP) - Tools: base64_encode, sha256_hash, get_timestamp, json_validate, url_encode - Prefix: `http_`

**Note**: Both servers use Streamable HTTP transport as required by the MCP Gateway broker. See [Transport Type Limitations](#transport-type-limitations) for details.

These servers use your custom MCP server implementations from the parent directory (`../sample-mcp-server-*`).

**Infrastructure:**
- MCP Broker: Aggregates tools from multiple upstream MCP servers
- MCP Router: Envoy external processor for request routing
- MCP Controller: Discovers servers via HTTPRoutes

## Architecture

```
Client → Gateway (Envoy) → Router (ext_proc) → Broker → Upstream MCP Servers
               ↑                                   ↑
          Controller → ConfigMap ──────────────────┘
```

The gateway provides tool aggregation, dynamic service discovery via Kubernetes Gateway API, and centralized routing.

## Usage

### Access the Gateway

```bash
# Port forward to broker
kubectl port-forward -n mcp-system svc/mcp-broker 8080:8080

# Initialize and get session ID
SESSION_ID=$(curl -s -i http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
      "protocolVersion": "2024-11-05",
      "capabilities": {},
      "clientInfo": {
        "name": "curl-client",
        "version": "1.0.0"
      }
    }
  }' | grep -i 'mcp-session-id:' | awk '{print $2}' | tr -d '\r')

echo "Session ID: $SESSION_ID"

# List all aggregated tools
curl http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "mcp-session-id: $SESSION_ID" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'

# Call a tool
curl http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "mcp-session-id: $SESSION_ID" \
  -d '{
    "jsonrpc": "2.0",
    "id": 3,
    "method": "tools/call",
    "params": {
      "name": "sse_calculate",
      "arguments": {
        "expression": "2+2"
      }
    }
  }'

# Check broker status (no session required)
curl http://localhost:8080/status | jq
```

### MCP Inspector

```bash
cd mcp-gateway
make inspect-gateway
```

### Monitor

```bash
# View server registrations
kubectl get mcpserverregistrations -n mcp-test

# Controller logs
kubectl logs -n mcp-system deployment/mcp-controller -f

# Broker logs
kubectl logs -n mcp-system deployment/mcp-broker-router -f
```

## MCPServerRegistration Example

```yaml
apiVersion: mcp.kagenti.com/v1alpha1
kind: MCPServerRegistration
metadata:
  name: sse-server
  namespace: mcp-test
spec:
  toolPrefix: sse_
  path: /sse
  targetRef:
    group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: mcp-server-sse-route
```

The controller discovers servers via HTTPRoute, generates configuration, and updates the broker.

## Important Notes

### Transport Type Limitations

**The MCP Gateway broker only supports Streamable HTTP transport for upstream MCP servers.** It does not currently support SSE (Server-Sent Events) transport.

This means:
- ✅ Upstream MCP servers must use `mcp.NewStreamableHTTPHandler()` (Go SDK) or equivalent
- ❌ Upstream MCP servers using `mcp.NewSSEHandler()` will fail with "sessionid must be provided" errors
- The broker uses `NewStreamableHttpClient()` to connect to upstream servers
- No configuration option exists to specify transport type in MCPServerRegistration

**Note**: While the sample directory includes a `sample-mcp-server-sse` implementation, it is currently incompatible with the MCP Gateway broker and will fail to register. Both deployed sample servers use Streamable HTTP transport.

If you need SSE support for upstream servers, consider:
1. Converting your MCP server to use Streamable HTTP transport
2. Filing a feature request with the [MCP Gateway project](https://github.com/Kuadrant/mcp-gateway/issues)

## Building Custom Images

If you want to build and use your own images:

```bash
# 1. Build images from mcp-gateway source
export DOCKER_USERNAME=your-username
export IMAGE_TAG=latest
./scripts/build-images.sh

# 2. Push to Docker Hub (requires: docker login)
./scripts/push-images.sh

# 3. Setup will automatically use your images
./setup-mcp-gateway.sh
```

The build script cross-compiles Go binaries from the `mcp-gateway/` submodule and creates Docker images.

## Cleanup

```bash
# Remove MCP servers only
./cleanup.sh

# Remove entire cluster (if using Kind)
./cleanup.sh --cluster
```

## Troubleshooting

**Pods not starting**: `kubectl logs -n mcp-system <pod-name>`

**Tools not showing up**:
- `kubectl describe mcpserverregistration <name> -n mcp-test`
- Check broker: `curl http://localhost:8080/status | jq`

**Gateway issues**: `kubectl get gateway -n mcp-system`

**MCPServerRegistration shows "sessionid must be provided" error**:
- This indicates your MCP server is using SSE transport instead of Streamable HTTP
- The MCP Gateway broker only supports Streamable HTTP for upstream servers
- Convert your server to use `mcp.NewStreamableHTTPHandler()` instead of `mcp.NewSSEHandler()`
- See [Transport Type Limitations](#transport-type-limitations) for more details

## Resources

- [MCP Gateway Documentation](https://github.com/Kuadrant/mcp-gateway)
- [Gateway API Documentation](https://gateway-api.sigs.k8s.io/)
- [Model Context Protocol Specification](https://modelcontextprotocol.io/)

## License

Experimental repository for the [MCP Gateway](https://github.com/Kuadrant/mcp-gateway) project (Apache 2.0).
