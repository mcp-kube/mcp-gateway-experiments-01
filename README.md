# MCP Gateway Kubernetes Experiments

Deploy and manage MCP (Model Context Protocol) servers on Kubernetes using the [MCP Gateway](https://github.com/Kuadrant/mcp-gateway).

**✅ SUCCESS**: This setup now uses **Istio** as recommended by MCP Gateway and **tool execution is fully working**! All MCP operations (`initialize`, `tools/list`, `tools/call`) are functional. See [Important Notes](#important-notes) for setup details.

**Note**: Experimental setup for learning and testing MCP Gateway capabilities.

## Quick Start

### Prerequisites

- kubectl connected to a Kubernetes cluster
- Docker (only needed if building custom images)
- **MCP Gateway source code**: Clone the [MCP Gateway repository](https://github.com/Kuadrant/mcp-gateway) into the `mcp-gateway/` subdirectory:
  ```bash
  git clone https://github.com/Kuadrant/mcp-gateway.git
  ```

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

**Sample MCP server:**

1. **Streamable HTTP Server** (Go SDK) - Tools: base64_encode, sha256_hash, get_timestamp, json_validate, url_encode - Prefix: `http_`

**Note**: The server uses Streamable HTTP transport as required by the MCP Gateway broker. See [Transport Type Limitations](#transport-type-limitations) for details.

This server uses your custom MCP server implementation from the parent directory (`../sample-mcp-server-streamable-http`).

**Infrastructure:**
- MCP Broker: Aggregates tools from multiple upstream MCP servers
- MCP Router: Envoy external processor for request routing
- MCP Controller: Discovers servers via HTTPRoutes

## Architecture

```
Client → Gateway (Istio) → Router (ext_proc) → Broker → Upstream MCP Servers
               ↑                                   ↑
          Controller → ConfigMap ──────────────────┘
```

The gateway provides tool aggregation, dynamic service discovery via Kubernetes Gateway API, and centralized routing.

**Current Setup**: Uses Istio Gateway with EnvoyFilter for ext_proc integration.

## Usage

### Understanding the Architecture

The MCP Gateway has two endpoints:

1. **Gateway Endpoint** (Istio + Router) - Port 8080 on `mcp-gateway-istio` service
   - Handles: `initialize`, `tools/list`, **`tools/call`** - ✅ All working
   - Routes tool calls to upstream servers via Istio/Envoy
   - **Use this for all MCP operations including tool execution**

2. **Broker Endpoint** - Port 8080 on `mcp-broker` service
   - Handles: `tools/list` (aggregation), status checks
   - **Does NOT forward tool calls** (returns error)
   - Only for monitoring and debugging
   - Works correctly when accessed directly for testing

### Access the Gateway

```bash
# Port forward to Istio Gateway
kubectl port-forward -n gateway-system svc/mcp-gateway-istio 8080:8080 &

# Note: The HTTPRoute requires hostname "mcp.127-0-0-1.sslip.io"
# Use this hostname in all requests (not localhost)

# Initialize and get session ID
SESSION_ID=$(curl -s -i http://mcp.127-0-0-1.sslip.io:8080/mcp \
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
curl http://mcp.127-0-0-1.sslip.io:8080/mcp \
  -H "Content-Type: application/json" \
  -H "mcp-session-id: $SESSION_ID" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'

# Call a tool (only works through Gateway, not Broker!)
curl http://mcp.127-0-0-1.sslip.io:8080/mcp \
  -H "Content-Type: application/json" \
  -H "mcp-session-id: $SESSION_ID" \
  -d '{
    "jsonrpc": "2.0",
    "id": 3,
    "method": "tools/call",
    "params": {
      "name": "http_base64_encode",
      "arguments": {
        "text": "Hello, MCP Gateway!"
      }
    }
  }'
```

### Check Broker Status (Monitoring Only)

```bash
# Port forward to broker for status/monitoring
kubectl port-forward -n mcp-system svc/mcp-broker 8080:8080

# Check broker status (no session required)
curl http://localhost:8080/status | jq
```

### MCP Inspector

```bash
# Port forward to the gateway first
kubectl port-forward -n gateway-system svc/mcp-gateway-istio 8080:8080 &

# Open MCP Inspector
npx @modelcontextprotocol/inspector http://mcp.127-0-0-1.sslip.io:8080/mcp
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
  name: streamable-http-server
  namespace: mcp-test
spec:
  toolPrefix: http_
  path: /mcp
  targetRef:
    group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: mcp-server-streamable-http-route
```

The controller discovers servers via HTTPRoute, generates configuration, and updates the broker.

## Important Notes

### ✅ Current Status with Istio

**SUCCESS**: This setup has been migrated to **Istio** as officially recommended by MCP Gateway and **all functionality is working**.

**Current Status with Istio:**
- ✅ Tool discovery (`tools/list`) - Works perfectly
- ✅ Server registration via MCPServerRegistration - Works
- ✅ Broker aggregation - Works
- ✅ ext_proc router processing - Works (logs show correct header manipulation)
- ✅ EnvoyFilter integration - Applied and configured correctly
- ✅ Tool execution (`tools/call`) - **Works perfectly!**

**What's Working:**
This experimental setup successfully demonstrates all MCP Gateway capabilities:
- Deploys the MCP Gateway components (Broker, Router, Controller) with Istio
- Discovers MCP servers via MCPServerRegistration CRDs
- Aggregates tools from multiple servers with prefixes
- Provides tool listing via `tools/list` endpoint
- ext_proc router correctly processes requests and sets routing headers (x-mcp-servername, x-mcp-method)
- **Tool execution routes correctly through Istio Gateway → ext_proc → Broker → Upstream MCP Servers**

**Key Configuration Requirements:**
1. HTTPRoutes must reference the Gateway in `gateway-system` namespace (not `mcp-system`)
2. Only one HTTPRoute per hostname (duplicate routes cause routing conflicts)
3. Upstream MCP servers must use Streamable HTTP transport (not SSE)

### Gateway vs Broker Endpoints

**Critical**: The MCP Gateway has two different endpoints with different capabilities:

- **Gateway Endpoint** (`mcp-gateway-istio` service in `gateway-system` namespace): Should handle ALL MCP operations including `tools/call` (currently broken)
- **Broker Endpoint** (`mcp-broker` service in `mcp-system` namespace): Only handles `tools/list` (aggregation) and monitoring - **does NOT execute tool calls**

The Gateway endpoint is intended for tool execution. The broker endpoint will return "Kagenti MCP Broker doesn't forward tool calls" error if you try to call tools through it. Direct broker access works for testing `initialize` and `tools/list`.

### Transport Type Limitations

**The MCP Gateway broker only supports Streamable HTTP transport for upstream MCP servers.** It does not currently support SSE (Server-Sent Events) transport.

This means:
- ✅ Upstream MCP servers must use `mcp.NewStreamableHTTPHandler()` (Go SDK) or equivalent
- ❌ Upstream MCP servers using `mcp.NewSSEHandler()` will fail with "sessionid must be provided" errors
- The broker uses `NewStreamableHttpClient()` to connect to upstream servers
- No configuration option exists to specify transport type in MCPServerRegistration

**Note**: While the parent directory includes a `sample-mcp-server-sse` implementation, it is currently incompatible with the MCP Gateway broker and is not deployed. Only the Streamable HTTP server is deployed in this setup.

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

**Tools/call returns errors**:
- Check that HTTPRoutes reference the Gateway in `gateway-system` namespace (not `mcp-system`)
- Ensure no duplicate HTTPRoutes exist for the same hostname (`kubectl get httproute -A`)
- Verify the upstream MCP server is running and healthy
- Check broker logs: `kubectl logs -n mcp-system deployment/mcp-broker-router -f`

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

**"Kagenti MCP Broker doesn't forward tool calls" error**:
- You're calling the **Broker endpoint** instead of the **Gateway endpoint**
- The broker only handles `tools/list` (aggregation) - it does NOT execute tool calls
- Tool calls must go through the Gateway (Istio + Router) endpoint
- Fix: Use the Istio Gateway service instead:
  ```bash
  kubectl port-forward -n gateway-system svc/mcp-gateway-istio 8080:8080
  ```
- See [Gateway vs Broker Endpoints](#gateway-vs-broker-endpoints) for details
- Note: Tool execution is currently broken even through the gateway (see troubleshooting above)

## Resources

- [MCP Gateway Documentation](https://github.com/Kuadrant/mcp-gateway)
- [Gateway API Documentation](https://gateway-api.sigs.k8s.io/)
- [Model Context Protocol Specification](https://modelcontextprotocol.io/)

## License

Experimental repository for the [MCP Gateway](https://github.com/Kuadrant/mcp-gateway) project (Apache 2.0).
