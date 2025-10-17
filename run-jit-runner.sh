#!/bin/bash
set -euo pipefail

JIT_CONFIG_FILE="jit-config.txt"
UNIQUE_LABEL="${UNIQUE_LABEL:-unknown}"

if [ ! -f "$JIT_CONFIG_FILE" ]; then
    echo "Error: JIT config file not found: $JIT_CONFIG_FILE"
    echo "Run ./generate-jit-config.sh first"
    exit 1
fi

JIT_CONFIG=$(cat "$JIT_CONFIG_FILE")
CONTAINER_NAME="jit-runner-${UNIQUE_LABEL}"

echo "=========================================="
echo "Starting GitHub Actions Runner with JIT Config"
echo "Unique Label: ${UNIQUE_LABEL}"
echo "Container: ${CONTAINER_NAME}"
echo "=========================================="
echo ""

# Stop and remove any existing container with same name
docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

echo "Starting Docker container..."
docker run -it --rm \
    --name "$CONTAINER_NAME" \
    -e JIT_CONFIG="$JIT_CONFIG" \
    -e UNIQUE_LABEL="$UNIQUE_LABEL" \
    jit-runner-spike:latest \
    /bin/bash -c '
        set -euo pipefail
        
        echo "=========================================="
        echo "GitHub Actions Runner - JIT Mode"
        echo "Unique Label: ${UNIQUE_LABEL}"
        echo "=========================================="
        echo ""
        
        echo "JIT Config (first 100 chars):"
        echo "${JIT_CONFIG:0:100}..."
        echo ""
        
        # Install runner dependencies
        echo "Installing runner dependencies..."
        sudo ./bin/installdependencies.sh || true
        
        echo ""
        echo "Starting runner with JIT configuration..."
        echo "⏳ Runner will:"
        echo "   1. Decode JIT config and extract unique label"
        echo "   2. Connect to GitHub"
        echo "   3. Wait for job with label: ${UNIQUE_LABEL}"
        echo "   4. Execute ONLY that job"
        echo "   5. Exit and self-destruct"
        echo ""
        echo "This runner will IGNORE jobs without the unique label!"
        echo "=========================================="
        echo ""
        
        # Run with JIT config
        ./run.sh --jitconfig "$JIT_CONFIG" --once
        
        EXIT_CODE=$?
        
        echo ""
        echo "=========================================="
        echo "Runner finished with exit code: $EXIT_CODE"
        echo "Label: ${UNIQUE_LABEL}"
        echo "=========================================="
        
        exit $EXIT_CODE
    '

echo ""
echo "Container exited. Check logs above for results."