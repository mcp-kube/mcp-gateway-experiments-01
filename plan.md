# Plan: Add Authentication & Authorization to MCP Gateway

## Goal
Add authentication and authorization to the MCP Gateway experiment to demonstrate:
1. MCP servers requiring credentials (API keys or OAuth tokens)
2. Gateway-level authentication for clients
3. End-to-end secure MCP communication

## Current State
- MCP Gateway deployed with Envoy Gateway provider
- 2 sample MCP servers (SSE and Streamable HTTP) deployed **without** authentication
- No client authentication required to access the gateway

## Proposed Changes

### Phase 1: Add Credentials to MCP Servers

**Approach**: Use API key authentication for MCP servers

1. **Create Kubernetes Secrets for server credentials**
   - Create secret for SSE server
   - Create secret for Streamable HTTP server
   - Secrets must have label `mcp.kagenti.com/credential=true`

2. **Update MCPServerRegistration resources**
   - Add `credentialRef` to both registrations
   - Point to the secrets created above

3. **Update sample server deployments**
   - Configure servers to require API keys (if not already configured)
   - May need to rebuild sample server images with auth enabled

**Expected Result**: MCP Gateway broker will authenticate to upstream servers using API keys

### Phase 2: Add Gateway-Level Authentication

**Approach**: Use Kuadrant Authorino for OAuth/OIDC authentication

1. **Deploy Keycloak for identity provider**
   - Can use existing MCP Gateway examples from `mcp-gateway/` repo
   - Deploy Keycloak to cluster
   - Configure realm and client

2. **Deploy Authorino (Gateway API authorization)**
   - Install Authorino operator
   - Create AuthPolicy for Gateway

3. **Configure AuthPolicy for MCP Gateway**
   - Attach AuthPolicy to the Gateway HTTPRoute
   - Configure OAuth token validation
   - Add API key validation as fallback

4. **Test authentication flow**
   - Obtain OAuth token from Keycloak
   - Use token to access MCP Gateway
   - Verify unauthorized requests are rejected

**Expected Result**: Clients must authenticate with OAuth token to access the gateway

### Phase 3: Test & Document

1. **Update test script** to handle authentication
   - Add token acquisition step
   - Pass Authorization header in requests

2. **Update README** with authentication instructions
   - How to get OAuth token
   - How to use API keys
   - Example curl commands with auth

3. **Add troubleshooting** for common auth issues

## Technical Details

### MCP Server Credentials Flow
```
1. Controller reads credentialRef secrets
2. Controller aggregates into mcp-aggregated-credentials secret
3. Broker mounts secret via env vars (KAGENTI_{NAME}_CRED)
4. Router adds Authorization header when routing to upstream servers
```

### Gateway Client Authentication Flow
```
1. Client requests OAuth token from Keycloak
2. Client calls MCP Gateway with Authorization header
3. Authorino validates token (via AuthPolicy)
4. If valid, request proceeds to ext_proc (Router)
5. Router routes to Broker
6. Broker calls upstream MCP servers (with server credentials)
```

### Known Issue: OAuth + API Key Conflict (Issue #201)
- ext_proc runs BEFORE AuthPolicy
- If ext_proc sets Authorization header, it overwrites OAuth token
- Solution: Router sets both `authorization` and `x-mcp-api-key` headers
- AuthPolicy validates OAuth token
- Upstream servers use `x-mcp-api-key` for their auth

## Implementation Steps

### Step 1: Create Server Credentials
```bash
# Create secret for SSE server
kubectl create secret generic sse-server-credentials \
  -n mcp-test \
  --from-literal=token="Bearer sse-secret-token" \
  --dry-run=client -o yaml | \
  kubectl label --dry-run=client -o yaml -f - \
    mcp.kagenti.com/credential=true | \
  kubectl apply -f -

# Create secret for HTTP server
kubectl create secret generic http-server-credentials \
  -n mcp-test \
  --from-literal=token="Bearer http-secret-token" \
  --dry-run=client -o yaml | \
  kubectl label --dry-run=client -o yaml -f - \
    mcp.kagenti.com/credential=true | \
  kubectl apply -f -
```

### Step 2: Update MCPServerRegistrations
Add to both registration files:
```yaml
spec:
  credentialRef:
    name: <server>-credentials
    key: token
```

### Step 3: Deploy Keycloak (for gateway auth)
```bash
# Use existing MCP Gateway setup
cd mcp-gateway
make oauth-token-exchange-example-setup
```

### Step 4: Create AuthPolicy
```yaml
apiVersion: kuadrant.io/v1beta2
kind: AuthPolicy
metadata:
  name: mcp-gateway-auth
  namespace: mcp-system
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: mcp-route
  rules:
    authentication:
      "keycloak-oauth":
        jwt:
          issuerUrl: http://keycloak.mcp-system.svc.cluster.local:8080/realms/mcp
```

## Questions to Resolve

1. **Do sample servers support authentication?**
   - Need to check if SSE/HTTP servers have auth enabled
   - May need to add auth support or use different test servers

2. **Gateway provider compatibility**
   - Currently using Envoy Gateway (not Istio)
   - Need to verify Authorino works with Envoy Gateway
   - May need to switch to Istio if required

3. **Keycloak deployment**
   - Can we reuse `make oauth-token-exchange-example-setup` from mcp-gateway?
   - Or deploy simpler Keycloak setup?

## References
- MCP Gateway OAuth example: `mcp-gateway/docs/guides/`
- Issue #201 (OAuth + API Key conflict): Documented in `mcp-gateway/CLAUDE.md`
- Authorino docs: https://docs.kuadrant.io/authorino/
