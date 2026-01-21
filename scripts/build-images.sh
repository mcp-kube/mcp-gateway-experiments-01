#!/bin/bash
set -e

# Build script for MCP Gateway container images
# This script cross-compiles Go binaries for amd64 and builds Docker images

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MCP_GATEWAY_DIR="$PROJECT_ROOT/mcp-gateway"

# Configuration
DOCKER_USERNAME="${DOCKER_USERNAME:-aliok}"
IMAGE_TAG="${IMAGE_TAG:-v1}"
GOARCH="${GOARCH:-amd64}"
GOOS="${GOOS:-linux}"

echo "========================================="
echo "Building MCP Gateway Images"
echo "========================================="
echo "Docker Username: $DOCKER_USERNAME"
echo "Image Tag: $IMAGE_TAG"
echo "Target Architecture: $GOOS/$GOARCH"
echo "========================================="

# Navigate to mcp-gateway directory
cd "$MCP_GATEWAY_DIR"

# Step 1: Cross-compile Go binaries for target architecture
echo ""
echo "[1/3] Cross-compiling Go binaries..."
echo "  - Building mcp-broker-router for $GOOS/$GOARCH"
GOARCH=$GOARCH GOOS=$GOOS CGO_ENABLED=0 go build \
  -o bin/mcp_gateway-$GOARCH \
  cmd/mcp-broker-router/main.go

echo "  - Building mcp-controller for $GOOS/$GOARCH"
GOARCH=$GOARCH GOOS=$GOOS CGO_ENABLED=0 go build \
  -o bin/mcp_controller-$GOARCH \
  cmd/main.go

echo "  ✓ Binaries built successfully"
ls -lh bin/mcp_*-$GOARCH

# Step 2: Build Docker images
echo ""
echo "[2/3] Building Docker images..."

# Create Dockerfile for gateway if it doesn't exist
if [ ! -f "Dockerfile.$GOARCH" ]; then
  echo "  - Creating Dockerfile.$GOARCH"
  cat > "Dockerfile.$GOARCH" <<EOF
FROM alpine:3.22.1

RUN apk --no-cache add ca-certificates

WORKDIR /app

COPY bin/mcp_gateway-$GOARCH ./mcp_gateway
RUN chmod +x mcp_gateway

EXPOSE 8080
EXPOSE 50051

ENTRYPOINT ["./mcp_gateway"]
EOF
fi

# Create Dockerfile for controller if it doesn't exist
if [ ! -f "Dockerfile.controller.$GOARCH" ]; then
  echo "  - Creating Dockerfile.controller.$GOARCH"
  cat > "Dockerfile.controller.$GOARCH" <<EOF
FROM alpine:3.22.1

RUN apk --no-cache add ca-certificates

WORKDIR /app

COPY bin/mcp_controller-$GOARCH ./mcp_controller
RUN chmod +x mcp_controller

EXPOSE 8081
EXPOSE 8082

ENTRYPOINT ["./mcp_controller"]
EOF
fi

echo "  - Building $DOCKER_USERNAME/mcp-gateway:$IMAGE_TAG"
docker build -f "Dockerfile.$GOARCH" -t "$DOCKER_USERNAME/mcp-gateway:$IMAGE_TAG" .

echo "  - Building $DOCKER_USERNAME/mcp-controller:$IMAGE_TAG"
docker build -f "Dockerfile.controller.$GOARCH" -t "$DOCKER_USERNAME/mcp-controller:$IMAGE_TAG" .

echo "  ✓ Images built successfully"

# Step 3: List built images
echo ""
echo "[3/3] Verifying images..."
docker images | grep -E "mcp-gateway|mcp-controller" | head -10

echo ""
echo "========================================="
echo "Build Complete!"
echo "========================================="
echo "Images:"
echo "  - $DOCKER_USERNAME/mcp-gateway:$IMAGE_TAG"
echo "  - $DOCKER_USERNAME/mcp-controller:$IMAGE_TAG"
echo ""
echo "Next steps:"
echo "  1. Push images: ./scripts/push-images.sh"
echo "  2. Deploy to cluster: ./scripts/deploy.sh"
echo "========================================="