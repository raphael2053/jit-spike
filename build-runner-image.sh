#!/bin/bash
set -euo pipefail

echo "Building GitHub Actions Runner Docker image..."
docker build -t jit-runner-spike:latest .
echo "✅ Image built successfully!"