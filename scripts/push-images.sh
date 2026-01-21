#!/bin/bash
set -e

# Push script for MCP Gateway container images
# Pushes images to Docker Hub or specified container registry

# Configuration
DOCKER_USERNAME="${DOCKER_USERNAME:-aliok}"
IMAGE_TAG="${IMAGE_TAG:-v1}"

echo "========================================="
echo "Pushing MCP Gateway Images"
echo "========================================="
echo "Docker Username: $DOCKER_USERNAME"
echo "Image Tag: $IMAGE_TAG"
echo "Registry: docker.io"
echo "========================================="

# Check if docker is logged in
if ! docker info > /dev/null 2>&1; then
  echo "Error: Docker daemon is not running or not accessible"
  exit 1
fi

# Verify images exist locally
echo ""
echo "[1/3] Verifying images exist locally..."
if ! docker image inspect "$DOCKER_USERNAME/mcp-gateway:$IMAGE_TAG" > /dev/null 2>&1; then
  echo "Error: Image $DOCKER_USERNAME/mcp-gateway:$IMAGE_TAG not found locally"
  echo "Please run ./scripts/build-images.sh first"
  exit 1
fi

if ! docker image inspect "$DOCKER_USERNAME/mcp-controller:$IMAGE_TAG" > /dev/null 2>&1; then
  echo "Error: Image $DOCKER_USERNAME/mcp-controller:$IMAGE_TAG not found locally"
  echo "Please run ./scripts/build-images.sh first"
  exit 1
fi
echo "  ✓ Images verified"

# Push mcp-gateway image
echo ""
echo "[2/3] Pushing $DOCKER_USERNAME/mcp-gateway:$IMAGE_TAG..."
docker push "$DOCKER_USERNAME/mcp-gateway:$IMAGE_TAG"
echo "  ✓ mcp-gateway pushed"

# Push mcp-controller image
echo ""
echo "[3/3] Pushing $DOCKER_USERNAME/mcp-controller:$IMAGE_TAG..."
docker push "$DOCKER_USERNAME/mcp-controller:$IMAGE_TAG"
echo "  ✓ mcp-controller pushed"

echo ""
echo "========================================="
echo "Push Complete!"
echo "========================================="
echo "Images pushed to Docker Hub:"
echo "  - docker.io/$DOCKER_USERNAME/mcp-gateway:$IMAGE_TAG"
echo "  - docker.io/$DOCKER_USERNAME/mcp-controller:$IMAGE_TAG"
echo ""
echo "Next steps:"
echo "  Deploy to cluster: ./scripts/deploy.sh"
echo "========================================="